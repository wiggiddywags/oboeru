import Foundation
import FSRS

// FSRSService wraps the swift-fsrs package (open-spaced-repetition/swift-fsrs v5.x).
//
// All FSRS types are top-level in the module — use Card, Rating, CardState, etc. directly.
// The scheduler class is also named FSRS, same as the module, so FSRS(parameters:) is the ctor.
//
// Key API:
//   scheduler.repeat(card:now:)          -> IPreview    (subscript with Rating -> RecordLogItem?)
//   scheduler.next(card:now:grade:)      throws -> RecordLogItem
//   scheduler.getRetrievability(card:now:) -> (string: String, number: Double)

final class FSRSService {

    // MARK: - Card bridge

    func fsrsCard(from card: OboerCard) -> Card {
        Card(
            due: card.fsrsDue,
            stability: card.fsrsStability,
            difficulty: card.fsrsDifficulty,
            elapsedDays: card.fsrsElapsedDays,
            scheduledDays: card.fsrsScheduledDays,
            reps: card.fsrsReps,
            lapses: card.fsrsLapses,
            state: CardState(rawValue: card.fsrsStateRaw) ?? .new,
            lastReview: card.fsrsLastReview
        )
    }

    func applyFSRS(_ fsrsCard: Card, to card: OboerCard) {
        card.fsrsDue           = fsrsCard.due
        card.fsrsStability     = fsrsCard.stability
        card.fsrsDifficulty    = fsrsCard.difficulty
        card.fsrsElapsedDays   = fsrsCard.elapsedDays
        card.fsrsScheduledDays = fsrsCard.scheduledDays
        card.fsrsReps          = fsrsCard.reps
        card.fsrsLapses        = fsrsCard.lapses
        card.fsrsStateRaw      = fsrsCard.state.rawValue
        card.fsrsLastReview    = fsrsCard.lastReview
    }

    // MARK: - Scheduling

    /// Returns an IPreview (subscriptable by Rating) without mutating the card.
    func previewRatings(for card: OboerCard, deck: Deck, now: Date = Date()) -> IPreview {
        makeScheduler(for: deck).repeat(card: fsrsCard(from: card), now: now)
    }

    /// Schedules the card for the given rating, mutates OboerCard, and returns a log entry.
    @discardableResult
    func applyRating(
        to card: OboerCard,
        rating: Rating,
        deck: Deck,
        now: Date = Date(),
        durationMs: Int = 0
    ) -> OboerReviewLog {
        let stateBefore = card.fsrsStateRaw
        // next() throws only for invalid state transitions; safe to try! here.
        let item = (try? makeScheduler(for: deck).next(card: fsrsCard(from: card), now: now, grade: rating))
            ?? makeScheduler(for: deck).repeat(card: fsrsCard(from: card), now: now)[rating]!

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
        makeScheduler(for: card.deck ?? Deck(name: ""))
            .getRetrievability(card: fsrsCard(from: card), now: now)
            .number
    }

    // MARK: - Private

    private func makeScheduler(for deck: Deck) -> FSRS {
        FSRS(parameters: FSRSParameters(
            requestRetention: deck.fsrsRequestRetention,
            maximumInterval: deck.fsrsMaxInterval
        ))
    }
}

// MARK: - Interval label helper

extension RecordLogItem {
    /// Human-readable next-interval label for rating buttons ("10 min", "3 days", etc.)
    var intervalLabel: String {
        let days = card.scheduledDays
        if days < 1.0 / 24 {
            let mins = max(1, Int(days * 24 * 60))
            return "\(mins) min"
        } else if days < 1 {
            let hrs = max(1, Int(days * 24))
            return "\(hrs) hr"
        } else if days < 30 {
            let d = max(1, Int(days.rounded()))
            return d == 1 ? "1 day" : "\(d) days"
        } else if days < 365 {
            let m = max(1, Int((days / 30).rounded()))
            return m == 1 ? "1 mo" : "\(m) mo"
        } else {
            let y = max(1, Int((days / 365).rounded()))
            return y == 1 ? "1 yr" : "\(y) yr"
        }
    }
}
