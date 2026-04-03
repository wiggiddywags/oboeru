import Foundation
import FSRS

// FSRSService is a stateless wrapper around the swift-fsrs package.
// It converts between SwiftData OboerCard scalars and the package's
// FSRS.Card value type — keeping the FSRS library isolated to this file.
//
// swift-fsrs package (open-spaced-repetition/swift-fsrs):
//   - FSRS.Card        value type with scheduling fields
//   - FSRS.Rating      enum: .again(1), .hard(2), .good(3), .easy(4)
//   - FSRS.CardState   enum: .new(0), .learning(1), .review(2), .relearning(3)
//   - FSRS.FSRS        scheduler: .repeat(card:now:) -> [Rating: RecordLogItem]
//   - FSRS.RecordLogItem  .card (Card) and .log (ReviewLog internal)

final class FSRSService {

    // MARK: - Card bridge

    func fsrsCard(from oboerCard: OboerCard) -> FSRS.Card {
        var c = FSRS.Card()
        c.due           = oboerCard.fsrsDue
        c.stability     = oboerCard.fsrsStability
        c.difficulty    = oboerCard.fsrsDifficulty
        c.elapsedDays   = oboerCard.fsrsElapsedDays
        c.scheduledDays = oboerCard.fsrsScheduledDays
        c.reps          = oboerCard.fsrsReps
        c.lapses        = oboerCard.fsrsLapses
        c.state         = FSRS.CardState(rawValue: oboerCard.fsrsStateRaw) ?? .new
        c.lastReview    = oboerCard.fsrsLastReview
        return c
    }

    func applyFSRS(_ fsrsCard: FSRS.Card, to oboerCard: OboerCard) {
        oboerCard.fsrsDue           = fsrsCard.due
        oboerCard.fsrsStability     = fsrsCard.stability
        oboerCard.fsrsDifficulty    = fsrsCard.difficulty
        oboerCard.fsrsElapsedDays   = fsrsCard.elapsedDays
        oboerCard.fsrsScheduledDays = fsrsCard.scheduledDays
        oboerCard.fsrsReps          = fsrsCard.reps
        oboerCard.fsrsLapses        = fsrsCard.lapses
        oboerCard.fsrsStateRaw      = fsrsCard.state.rawValue
        oboerCard.fsrsLastReview    = fsrsCard.lastReview
    }

    // MARK: - Scheduling

    /// Returns previews for all four ratings without mutating the card.
    /// Keys: FSRS.Rating (.again, .hard, .good, .easy)
    func previewRatings(
        for card: OboerCard,
        deck: Deck,
        now: Date = Date()
    ) -> [FSRS.Rating: FSRS.RecordLogItem] {
        let scheduler = makeScheduler(for: deck)
        return scheduler.`repeat`(card: fsrsCard(from: card), now: now)
    }

    /// Applies a rating to the OboerCard (mutates in place) and returns a
    /// log entry ready to be inserted into the ModelContext.
    @discardableResult
    func applyRating(
        to card: OboerCard,
        rating: FSRS.Rating,
        deck: Deck,
        now: Date = Date(),
        durationMs: Int = 0
    ) -> OboerReviewLog {
        let scheduler = makeScheduler(for: deck)
        let previews = scheduler.`repeat`(card: fsrsCard(from: card), now: now)
        guard let item = previews[rating] else {
            fatalError("FSRS.repeat() did not return a result for rating \(rating)")
        }
        let stateBefore = card.fsrsStateRaw
        applyFSRS(item.card, to: card)
        card.updatedAt = now
        return OboerReviewLog(
            card: card,
            rating: rating.rawValue,
            stateBefore: stateBefore,
            stateAfter: item.card.state.rawValue,
            scheduledDays: item.card.scheduledDays,
            elapsedDays: item.card.elapsedDays,
            stability: item.card.stability,
            difficulty: item.card.difficulty,
            durationMs: durationMs
        )
    }

    /// Estimated probability of recall right now (0–1).
    func retrievability(for card: OboerCard, now: Date = Date()) -> Double {
        let scheduler = makeScheduler(for: card.deck ?? Deck(name: ""))
        return scheduler.getRetrievability(card: fsrsCard(from: card), now: now)
    }

    // MARK: - Private

    private func makeScheduler(for deck: Deck) -> FSRS.FSRS {
        var params = FSRS.FSRSParameters()
        params.requestRetention = deck.fsrsRequestRetention
        params.maximumInterval  = deck.fsrsMaxInterval
        return FSRS.FSRS(parameters: params)
    }
}

// MARK: - Interval formatting helper

extension FSRS.RecordLogItem {
    /// Human-readable interval label for the rating button (e.g. "10 min", "3 days").
    var intervalLabel: String {
        let days = card.scheduledDays
        if days < 1.0 / 24 {
            let mins = Int(days * 24 * 60)
            return "\(max(1, mins)) min"
        } else if days < 1 {
            let hours = Int(days * 24)
            return "\(max(1, hours)) hr"
        } else if days < 30 {
            let d = Int(days.rounded())
            return d == 1 ? "1 day" : "\(d) days"
        } else if days < 365 {
            let m = Int((days / 30).rounded())
            return m == 1 ? "1 mo" : "\(m) mo"
        } else {
            let y = Int((days / 365).rounded())
            return y == 1 ? "1 yr" : "\(y) yr"
        }
    }
}
