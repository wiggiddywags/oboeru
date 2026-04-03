import Foundation
import SwiftData

@Model
final class OboerReviewLog {
    var id: UUID
    var card: OboerCard?
    var deck: Deck?             // denormalized for fast stats queries
    var reviewedAt: Date

    // Rating: 1=Again, 2=Hard, 3=Good, 4=Easy (mirrors FSRS.Rating.rawValue)
    var rating: Int

    var stateBefore: Int        // OboerCardState.rawValue
    var stateAfter: Int         // OboerCardState.rawValue
    var scheduledDays: Double
    var elapsedDays: Double
    var stability: Double
    var difficulty: Double
    var durationMs: Int         // time spent on the card in milliseconds

    init(
        card: OboerCard,
        rating: Int,
        stateBefore: Int,
        stateAfter: Int,
        scheduledDays: Double,
        elapsedDays: Double,
        stability: Double,
        difficulty: Double,
        durationMs: Int = 0
    ) {
        self.id = UUID()
        self.card = card
        self.deck = card.deck
        self.reviewedAt = Date()
        self.rating = rating
        self.stateBefore = stateBefore
        self.stateAfter = stateAfter
        self.scheduledDays = scheduledDays
        self.elapsedDays = elapsedDays
        self.stability = stability
        self.difficulty = difficulty
        self.durationMs = durationMs
    }
}

// MARK: - Convenience

extension OboerReviewLog {
    /// True if the user successfully recalled the card (Good or Easy)
    var wasSuccessful: Bool { rating >= 3 }
}
