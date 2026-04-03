import Foundation
import SwiftData

@Model
final class Deck {
    var id: UUID
    var name: String
    var colorHex: String        // e.g. "#5E9CF0"
    var iconName: String        // SF Symbol name
    var createdAt: Date
    var updatedAt: Date
    var fsrsRequestRetention: Double    // default 0.9
    var fsrsMaxInterval: Double         // default 36500 days (~100 years)
    var isArchived: Bool

    @Relationship(deleteRule: .cascade, inverse: \OboerCard.deck)
    var cards: [OboerCard]

    init(
        name: String,
        colorHex: String = "#5E9CF0",
        iconName: String = "rectangle.stack"
    ) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.iconName = iconName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.fsrsRequestRetention = 0.9
        self.fsrsMaxInterval = 36500
        self.isArchived = false
        self.cards = []
    }
}

// MARK: - Convenience

extension Deck {
    var nonSuspendedCards: [OboerCard] {
        cards.filter { !$0.isSuspended }
    }

    var dueCards: [OboerCard] {
        let now = Date()
        return nonSuspendedCards.filter { $0.fsrsDue <= now }
    }
}
