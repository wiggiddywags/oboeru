import Foundation
import SwiftData

@Observable
final class CardEditorViewModel {

    var cardType: CardType = .basic
    var frontText: String = ""
    var backText: String = ""
    var clozeText: String = ""
    var clozeIsValid: Bool = false
    var clozeSiblingCount: Int = 0

    private let existingCard: OboerCard?
    private let deck: Deck
    private let modelContext: ModelContext

    var isEditing: Bool { existingCard != nil }

    init(editing card: OboerCard? = nil, deck: Deck, modelContext: ModelContext) {
        self.existingCard = card
        self.deck = deck
        self.modelContext = modelContext

        if let card {
            self.cardType  = card.cardType
            self.frontText = card.frontText
            self.backText  = card.backText
            self.clozeText = card.clozeText ?? ""
        }
    }

    // MARK: - Validation

    var canSave: Bool {
        switch cardType {
        case .basic:
            return !frontText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .cloze:
            return clozeIsValid
        }
    }

    // Call from .onChange(of: clozeText)
    func updateClozePreview() {
        clozeIsValid = ClozeParser.isValid(clozeText)
        clozeSiblingCount = ClozeParser.gapCount(clozeText)
    }

    // MARK: - Save

    func save() throws {
        switch cardType {
        case .basic:
            try saveBasic()
        case .cloze:
            try saveCloze()
        }
    }

    private func saveBasic() throws {
        if let card = existingCard {
            card.frontText = frontText.trimmingCharacters(in: .whitespacesAndNewlines)
            card.backText  = backText.trimmingCharacters(in: .whitespacesAndNewlines)
            card.updatedAt = Date()
        } else {
            let card = OboerCard(
                deck: deck,
                cardType: .basic,
                frontText: frontText.trimmingCharacters(in: .whitespacesAndNewlines),
                backText: backText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            modelContext.insert(card)
        }
        try modelContext.save()
    }

    private func saveCloze() throws {
        let raw = clozeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let newSiblings = ClozeParser.siblings(for: raw)

        if let existingCard {
            // We're editing the "primary" sibling (ordinal == 1 in the simplest case).
            // Find all sibling cards that share the same clozeText source in this deck.
            let existingOrdinal = existingCard.clozeOrdinal
            let deckCards = deck.cards.filter {
                $0.cardType == .cloze && $0.clozeText == (existingCard.clozeText ?? "")
            }

            // Update or delete existing siblings
            for sibling in deckCards {
                if let match = newSiblings.first(where: { $0.ordinal == sibling.clozeOrdinal }) {
                    sibling.clozeText = raw
                    sibling.frontText = match.maskedText
                    sibling.backText  = match.fullText
                    sibling.updatedAt = Date()
                } else {
                    modelContext.delete(sibling)
                }
            }

            // Insert new siblings that didn't exist before
            let existingOrdinals = Set(deckCards.map(\.clozeOrdinal))
            for sibling in newSiblings where !existingOrdinals.contains(sibling.ordinal) {
                let card = OboerCard(
                    deck: deck,
                    cardType: .cloze,
                    frontText: sibling.maskedText,
                    backText: sibling.fullText,
                    clozeText: raw,
                    clozeOrdinal: sibling.ordinal
                )
                modelContext.insert(card)
            }
            _ = existingOrdinal  // suppress unused warning
        } else {
            // New cloze card — insert all siblings
            for sibling in newSiblings {
                let card = OboerCard(
                    deck: deck,
                    cardType: .cloze,
                    frontText: sibling.maskedText,
                    backText: sibling.fullText,
                    clozeText: raw,
                    clozeOrdinal: sibling.ordinal
                )
                modelContext.insert(card)
            }
        }

        try modelContext.save()
    }
}
