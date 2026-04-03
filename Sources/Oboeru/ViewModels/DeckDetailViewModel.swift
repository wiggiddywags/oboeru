import Foundation
import SwiftData

@Observable
final class DeckDetailViewModel {

    let deck: Deck
    private(set) var cards: [OboerCard] = []
    var searchText: String = ""
    var filterState: FilterState = .all
    var isShowingCardEditor = false
    var editingCard: OboerCard?

    enum FilterState: String, CaseIterable {
        case all = "All"
        case due = "Due"
        case suspended = "Suspended"
        case new = "New"
    }

    private let modelContext: ModelContext

    init(deck: Deck, modelContext: ModelContext) {
        self.deck = deck
        self.modelContext = modelContext
    }

    // MARK: - Load

    func load() {
        let deckID = deck.id
        var descriptor = FetchDescriptor<OboerCard>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        descriptor.predicate = #Predicate { card in
            card.deck?.id == deckID
        }
        cards = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Filtered view

    func filteredCards() -> [OboerCard] {
        var result = cards

        // Filter by state
        let now = Date()
        switch filterState {
        case .all:
            break
        case .due:
            result = result.filter { $0.fsrsDue <= now && !$0.isSuspended }
        case .suspended:
            result = result.filter { $0.isSuspended }
        case .new:
            result = result.filter { $0.fsrsState == .new }
        }

        // Search
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.frontText.lowercased().contains(q) ||
                $0.backText.lowercased().contains(q) ||
                ($0.clozeText?.lowercased().contains(q) ?? false)
            }
        }

        return result
    }

    // MARK: - CRUD

    func createBasicCard(front: String, back: String) {
        let card = OboerCard(deck: deck, cardType: .basic, frontText: front, backText: back)
        modelContext.insert(card)
        try? modelContext.save()
        load()
    }

    func deleteCard(_ card: OboerCard) {
        modelContext.delete(card)
        try? modelContext.save()
        load()
    }

    func suspendCard(_ card: OboerCard, suspended: Bool) {
        card.isSuspended = suspended
        try? modelContext.save()
    }

    func resetCardSchedule(_ card: OboerCard) {
        card.fsrsStateRaw = OboerCardState.new.rawValue
        card.fsrsDue = Date()
        card.fsrsStability = 0
        card.fsrsDifficulty = 0
        card.fsrsElapsedDays = 0
        card.fsrsScheduledDays = 0
        card.fsrsReps = 0
        card.fsrsLapses = 0
        card.fsrsLastReview = nil
        card.updatedAt = Date()
        try? modelContext.save()
    }

    // MARK: - New card shortcut

    func newCardForEditing() {
        editingCard = nil
        isShowingCardEditor = true
    }
}
