import Foundation
import SwiftData
import FSRS

// StudySession orchestrates a review session from queue building to completion.
// It is @Observable so ReviewSessionView can bind to phase/progress directly.

@Observable
final class StudySession {

    // MARK: - Phase

    enum Phase: Equatable {
        case loading
        case front
        case back(previews: RatingPreviews)
        case finished(summary: SessionSummary)

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.loading, .loading), (.front, .front): return true
            case (.back, .back): return true
            case (.finished, .finished): return true
            default: return false
            }
        }
    }

    struct RatingPreviews {
        let again: RecordLogItem
        let hard:  RecordLogItem
        let good:  RecordLogItem
        let easy:  RecordLogItem
    }

    struct SessionSummary {
        let totalReviewed: Int
        let againCount: Int
        let hardCount: Int
        let goodCount: Int
        let easyCount: Int
        let newCardsStudied: Int
        let duration: TimeInterval
    }

    // MARK: - Observable state

    private(set) var phase: Phase = .loading
    private(set) var currentCard: OboerCard?
    private(set) var remainingCount: Int = 0
    private(set) var progress: Double = 0

    // MARK: - Config

    let decks: [Deck]
    private let interleavingEnabled: Bool
    private let interleavingBlockSize: Int
    private let newCardLimit: Int
    private let reviewLimit: Int

    // MARK: - Dependencies

    private let fsrsService: FSRSService
    private let modelContext: ModelContext

    // MARK: - Internal queue & stats

    private var queue: [OboerCard] = []
    private var totalQueueSize: Int = 0
    private var interleavingState: InterleavingState?
    private var cardStartTime: Date = Date()
    private var sessionStartTime: Date = Date()
    private var mutableStats = MutableStats()

    // MARK: - Init

    init(
        decks: [Deck],
        settings: AppSettings,
        fsrsService: FSRSService,
        modelContext: ModelContext
    ) {
        self.decks = decks
        self.interleavingEnabled = settings.interleavingEnabled
        self.interleavingBlockSize = settings.interleavingBlockSize
        self.newCardLimit = settings.dailyNewCardLimit
        self.reviewLimit = settings.dailyReviewLimit
        self.fsrsService = fsrsService
        self.modelContext = modelContext
    }

    // MARK: - Public API

    func start() {
        sessionStartTime = Date()
        buildQueue()
        nextCard()
    }

    func showAnswer() {
        guard case .front = phase, let card = currentCard else { return }
        let deck = card.deck ?? decks.first!
        let preview = fsrsService.previewRatings(for: card, deck: deck)
        guard
            let again = preview[.again],
            let hard  = preview[.hard],
            let good  = preview[.good],
            let easy  = preview[.easy]
        else { return }
        phase = .back(previews: RatingPreviews(again: again, hard: hard, good: good, easy: easy))
    }

    func rate(_ rating: Rating) {
        guard case .back = phase, let card = currentCard else { return }
        let durationMs = Int(Date().timeIntervalSince(cardStartTime) * 1000)
        let deck = card.deck ?? decks.first!
        let wasNew = card.isNew

        let log = fsrsService.applyRating(
            to: card,
            rating: rating,
            deck: deck,
            now: Date(),
            durationMs: durationMs
        )
        modelContext.insert(log)
        try? modelContext.save()

        mutableStats.record(rating: rating, wasNew: wasNew)

        // Re-insert cards rated "Again" ~10 positions ahead so they resurface soon.
        if rating == Rating.again && queue.count > 2 {
            let insertAt = min(queue.count, 10)
            queue.insert(card, at: insertAt)
            totalQueueSize += 1
        }

        nextCard()
    }

    // MARK: - Queue building

    private func buildQueue() {
        let now = Date()
        let todayStart = Calendar.current.startOfDay(for: now)

        // Count cards already reviewed today (for daily limits)
        let todayLogDescriptor = FetchDescriptor<OboerReviewLog>(
            predicate: #Predicate { log in log.reviewedAt >= todayStart }
        )
        let todayLogs = (try? modelContext.fetch(todayLogDescriptor)) ?? []
        let reviewedTodayCount = todayLogs.filter { $0.stateBefore != OboerCardState.new.rawValue }.count
        let newTodayCount = todayLogs.filter { $0.stateBefore == OboerCardState.new.rawValue }.count

        let remainingNew     = max(0, newCardLimit    - newTodayCount)
        let remainingReviews = max(0, reviewLimit     - reviewedTodayCount)

        // Fetch due cards per deck
        var deckQueues: [UUID: [OboerCard]] = [:]

        for deck in decks {
            let deckCards = deck.cards.filter { !$0.isSuspended }

            var reviewCards = deckCards
                .filter { $0.fsrsState != .new && $0.fsrsDue <= now }
                .sorted { $0.fsrsDue < $1.fsrsDue }

            var newCards = deckCards
                .filter { $0.fsrsState == .new }
                .sorted { $0.createdAt < $1.createdAt }

            // Apply limits (shared across all decks proportionally — simple approach)
            if reviewCards.count > remainingReviews {
                reviewCards = Array(reviewCards.prefix(remainingReviews))
            }
            if newCards.count > remainingNew {
                newCards = Array(newCards.prefix(remainingNew))
            }

            deckQueues[deck.id] = reviewCards + newCards
        }

        if interleavingEnabled && decks.count > 1 {
            interleavingState = InterleavingState(
                deckQueues: deckQueues,
                deckOrder: decks.map(\.id),
                blockSize: interleavingBlockSize
            )
            queue = []
        } else {
            // Flat queue: all decks merged, reviews first then new
            queue = deckQueues.values.flatMap { $0 }
        }

        totalQueueSize = queue.count + (interleavingState?.totalRemaining ?? 0)
        remainingCount = totalQueueSize
    }

    private func nextCard() {
        if let interleaving = interleavingState {
            if let card = interleaving.next() {
                currentCard = card
                cardStartTime = Date()
                phase = .front
                remainingCount -= 1
                progress = totalQueueSize > 0 ? Double(totalQueueSize - remainingCount) / Double(totalQueueSize) : 1
                return
            }
        } else if !queue.isEmpty {
            let card = queue.removeFirst()
            currentCard = card
            cardStartTime = Date()
            phase = .front
            remainingCount -= 1
            progress = totalQueueSize > 0 ? Double(totalQueueSize - remainingCount) / Double(totalQueueSize) : 1
            return
        }

        // Session complete
        let duration = Date().timeIntervalSince(sessionStartTime)
        phase = .finished(summary: SessionSummary(
            totalReviewed: mutableStats.total,
            againCount: mutableStats.again,
            hardCount: mutableStats.hard,
            goodCount: mutableStats.good,
            easyCount: mutableStats.easy,
            newCardsStudied: mutableStats.newCards,
            duration: duration
        ))
        progress = 1.0
    }
}

// MARK: - Interleaving

private class InterleavingState {

    private var deckQueues: [UUID: [OboerCard]]
    private var deckOrder: [UUID]
    private var currentDeckIndex: Int = 0
    private var dealtFromCurrentDeck: Int = 0
    let blockSize: Int

    var totalRemaining: Int {
        deckQueues.values.map(\.count).reduce(0, +)
    }

    init(deckQueues: [UUID: [OboerCard]], deckOrder: [UUID], blockSize: Int) {
        self.deckQueues = deckQueues
        self.deckOrder = deckOrder.filter { deckQueues[$0]?.isEmpty == false }
        self.blockSize = blockSize
    }

    func next() -> OboerCard? {
        guard !deckOrder.isEmpty else { return nil }

        // Skip to next non-empty deck if needed
        var attempts = 0
        while attempts < deckOrder.count {
            let deckID = deckOrder[currentDeckIndex % deckOrder.count]
            if dealtFromCurrentDeck >= blockSize || (deckQueues[deckID]?.isEmpty ?? true) {
                advanceDeck()
                attempts += 1
                continue
            }
            if let card = deckQueues[deckID]?.first {
                deckQueues[deckID]?.removeFirst()
                dealtFromCurrentDeck += 1
                // Remove exhausted decks from order
                if deckQueues[deckID]?.isEmpty == true {
                    deckOrder.removeAll { $0 == deckID }
                    if currentDeckIndex >= deckOrder.count { currentDeckIndex = 0 }
                    dealtFromCurrentDeck = 0
                }
                return card
            }
            break
        }
        return nil
    }

    private func advanceDeck() {
        dealtFromCurrentDeck = 0
        if !deckOrder.isEmpty {
            currentDeckIndex = (currentDeckIndex + 1) % deckOrder.count
        }
    }
}

// MARK: - Mutable stats accumulator

private struct MutableStats {
    var again = 0
    var hard = 0
    var good = 0
    var easy = 0
    var newCards = 0
    var total = 0

    mutating func record(rating: Rating, wasNew: Bool) {
        total += 1
        if wasNew { newCards += 1 }
        switch rating {
        case .again: again += 1
        case .hard:  hard += 1
        case .good:  good += 1
        case .easy:  easy += 1
        }
    }
}
