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

    // Rich text (RTF data — nil for plain text cards)
    var frontRTFData: Data? = nil
    var backRTFData: Data? = nil

    // Images / GIFs
    var frontImageData: Data? = nil
    var backImageData: Data? = nil

    // Audio
    var frontAudioData: Data? = nil
    var frontAudioExt: String? = nil
    var backAudioData: Data? = nil
    var backAudioExt: String? = nil

    // Video
    var frontVideoData: Data? = nil
    var frontVideoExt: String? = nil
    var backVideoData: Data? = nil
    var backVideoExt: String? = nil

    private let existingCard: OboerCard?
    private let deck: Deck
    private let modelContext: ModelContext

    var isEditing: Bool { existingCard != nil }

    init(editing card: OboerCard? = nil, deck: Deck, modelContext: ModelContext) {
        self.existingCard = card
        self.deck = deck
        self.modelContext = modelContext

        if let card {
            self.cardType       = card.cardType
            self.frontText      = card.frontText
            self.backText       = card.backText
            self.clozeText      = card.clozeText ?? ""
            self.frontRTFData   = card.frontRTFData
            self.backRTFData    = card.backRTFData
            self.frontImageData = card.frontImageData
            self.backImageData  = card.backImageData
            self.frontAudioData = card.frontAudioData
            self.frontAudioExt  = card.frontAudioExt
            self.backAudioData  = card.backAudioData
            self.backAudioExt   = card.backAudioExt
            self.frontVideoData = card.frontVideoData
            self.frontVideoExt  = card.frontVideoExt
            self.backVideoData  = card.backVideoData
            self.backVideoExt   = card.backVideoExt
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
        case .basic:  try saveBasic()
        case .cloze:  try saveCloze()
        }
    }

    private func applyMedia(to card: OboerCard) {
        card.frontRTFData   = frontRTFData
        card.backRTFData    = backRTFData
        card.frontImageData = frontImageData
        card.backImageData  = backImageData
        card.frontAudioData = frontAudioData
        card.frontAudioExt  = frontAudioExt
        card.backAudioData  = backAudioData
        card.backAudioExt   = backAudioExt
        card.frontVideoData = frontVideoData
        card.frontVideoExt  = frontVideoExt
        card.backVideoData  = backVideoData
        card.backVideoExt   = backVideoExt
    }

    private func saveBasic() throws {
        if let card = existingCard {
            card.frontText = frontText.trimmingCharacters(in: .whitespacesAndNewlines)
            card.backText  = backText.trimmingCharacters(in: .whitespacesAndNewlines)
            card.updatedAt = Date()
            applyMedia(to: card)
        } else {
            let card = OboerCard(
                deck: deck,
                cardType: .basic,
                frontText: frontText.trimmingCharacters(in: .whitespacesAndNewlines),
                backText: backText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            applyMedia(to: card)
            modelContext.insert(card)
        }
        try modelContext.save()
    }

    private func saveCloze() throws {
        let raw = clozeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let newSiblings = ClozeParser.siblings(for: raw)

        if let existingCard {
            let existingOrdinal = existingCard.clozeOrdinal
            let deckCards = deck.cards.filter {
                $0.cardType == .cloze && $0.clozeText == (existingCard.clozeText ?? "")
            }

            for sibling in deckCards {
                if let match = newSiblings.first(where: { $0.ordinal == sibling.clozeOrdinal }) {
                    sibling.clozeText = raw
                    sibling.frontText = match.maskedText
                    sibling.backText  = match.fullText
                    sibling.updatedAt = Date()
                    applyMedia(to: sibling)
                } else {
                    modelContext.delete(sibling)
                }
            }

            let existingOrdinals = Set(deckCards.map(\.clozeOrdinal))
            for sibling in newSiblings where !existingOrdinals.contains(sibling.ordinal) {
                let card = OboerCard(
                    deck: deck, cardType: .cloze,
                    frontText: sibling.maskedText, backText: sibling.fullText,
                    clozeText: raw, clozeOrdinal: sibling.ordinal
                )
                applyMedia(to: card)
                modelContext.insert(card)
            }
            _ = existingOrdinal
        } else {
            for sibling in newSiblings {
                let card = OboerCard(
                    deck: deck, cardType: .cloze,
                    frontText: sibling.maskedText, backText: sibling.fullText,
                    clozeText: raw, clozeOrdinal: sibling.ordinal
                )
                applyMedia(to: card)
                modelContext.insert(card)
            }
        }

        try modelContext.save()
    }
}
