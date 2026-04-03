import Foundation
import SwiftData

enum CardType: String, Codable, CaseIterable {
    case basic
    case cloze
}

/// FSRS card states (mirrors FSRS.CardState)
enum OboerCardState: Int, Codable {
    case new = 0
    case learning = 1
    case review = 2
    case relearning = 3

    var displayName: String {
        switch self {
        case .new: "New"
        case .learning: "Learning"
        case .review: "Review"
        case .relearning: "Relearning"
        }
    }
}

// Named OboerCard to avoid collision with FSRS.Card from the swift-fsrs package.
@Model
final class OboerCard {
    var id: UUID
    var deck: Deck?
    var cardType: CardType

    // Basic card content
    var frontText: String
    var backText: String

    // Cloze card content
    // Full source text with {{gap::hint?}} markers.
    // Each unique ordinal (1..N) produces a separate sibling OboerCard.
    var clozeText: String?
    // Which cloze ordinal this card tests. 0 = basic card.
    var clozeOrdinal: Int

    var isSuspended: Bool
    var createdAt: Date
    var updatedAt: Date

    // FSRS scheduling state — raw scalars so SwiftData can persist them.
    // These mirror the fields of FSRS.Card from the swift-fsrs package.
    var fsrsDue: Date
    var fsrsStability: Double
    var fsrsDifficulty: Double
    var fsrsElapsedDays: Double
    var fsrsScheduledDays: Double
    var fsrsReps: Int
    var fsrsLapses: Int
    var fsrsStateRaw: Int           // OboerCardState.rawValue
    var fsrsLastReview: Date?

    @Relationship(deleteRule: .cascade, inverse: \OboerReviewLog.card)
    var reviewLogs: [OboerReviewLog]

    init(
        deck: Deck,
        cardType: CardType,
        frontText: String = "",
        backText: String = "",
        clozeText: String? = nil,
        clozeOrdinal: Int = 0
    ) {
        self.id = UUID()
        self.deck = deck
        self.cardType = cardType
        self.frontText = frontText
        self.backText = backText
        self.clozeText = clozeText
        self.clozeOrdinal = clozeOrdinal
        self.isSuspended = false
        self.createdAt = Date()
        self.updatedAt = Date()
        // FSRS initial state — new card, due immediately
        self.fsrsDue = Date()
        self.fsrsStability = 0
        self.fsrsDifficulty = 0
        self.fsrsElapsedDays = 0
        self.fsrsScheduledDays = 0
        self.fsrsReps = 0
        self.fsrsLapses = 0
        self.fsrsStateRaw = OboerCardState.new.rawValue
        self.fsrsLastReview = nil
        self.reviewLogs = []
    }
}

// MARK: - Convenience

extension OboerCard {
    var fsrsState: OboerCardState {
        OboerCardState(rawValue: fsrsStateRaw) ?? .new
    }

    var isNew: Bool { fsrsState == .new }
    var isDue: Bool { fsrsDue <= Date() }

    /// Display text for the front of the card (works for both basic and cloze).
    var displayFront: String {
        switch cardType {
        case .basic:
            return frontText
        case .cloze:
            guard let raw = clozeText else { return frontText }
            return ClozeParser.renderMasked(raw, ordinal: clozeOrdinal)
        }
    }

    /// Display text for the back / revealed answer.
    var displayBack: String {
        switch cardType {
        case .basic:
            return backText
        case .cloze:
            return clozeText ?? backText
        }
    }
}
