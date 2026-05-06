import Foundation
import SwiftData

// DeckShareService exports a Deck (and all its cards) to a portable `.oboeru` JSON
// package file, and imports such a file back into a SwiftData ModelContext.
//
// Design notes:
// - FSRS scheduling state is intentionally excluded from the package; imported cards
//   start as new cards with no history.
// - Media (images, audio) is base64-encoded inside the JSON. For large decks this
//   increases file size significantly; the caller may want to warn the user.
// - The package version is 1. Future breaking changes should increment this number.

// MARK: - Package types

struct OboerPackage: Codable {
    /// Bump when the schema changes in a backwards-incompatible way.
    let version: Int            // currently 1
    let exportedAt: Date
    let deck: DeckPackage
    let cards: [CardPackage]
}

struct DeckPackage: Codable {
    let name: String
    let colorHex: String
    let iconName: String
}

struct CardPackage: Codable {
    let id: String              // UUID string
    let cardType: String        // "basic" or "cloze"
    let frontText: String
    let backText: String
    let clozeText: String?
    let clozeOrdinal: Int
    let tags: [String]
    let isReversed: Bool

    // Optional media — base64-encoded binary, nil if absent
    let frontImageData: String?
    let backImageData: String?
    let frontAudioData: String?
    let frontAudioExt: String?
    let backAudioData: String?
    let backAudioExt: String?
}

// MARK: - Errors

enum DeckShareError: LocalizedError {
    case encodingFailed(String)
    case decodingFailed(String)
    case unsupportedVersion(Int)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed(let msg):    return "Export failed: \(msg)"
        case .decodingFailed(let msg):    return "Import failed: \(msg)"
        case .unsupportedVersion(let v):  return "Unsupported package version \(v). Please update Oboeru."
        case .saveFailed(let msg):        return "Could not save file: \(msg)"
        }
    }
}

// MARK: - Service

enum DeckShareService {

    private static let currentVersion = 1

    // MARK: - Export

    /// Encodes `deck` (and all its non-suspended cards) as an `OboerPackage` JSON blob.
    /// Throws `DeckShareError.encodingFailed` on serialisation failure.
    static func export(deck: Deck) throws -> Data {
        let deckPackage = DeckPackage(
            name:      deck.name,
            colorHex:  deck.colorHex,
            iconName:  deck.iconName
        )

        let cardPackages: [CardPackage] = deck.cards.map { card in
            CardPackage(
                id:             card.id.uuidString,
                cardType:       card.cardType.rawValue,
                frontText:      card.frontText,
                backText:       card.backText,
                clozeText:      card.clozeText,
                clozeOrdinal:   card.clozeOrdinal,
                tags:           card.tags,
                isReversed:     card.isReversed,
                frontImageData: card.frontImageData.map { $0.base64EncodedString() },
                backImageData:  card.backImageData.map  { $0.base64EncodedString() },
                frontAudioData: card.frontAudioData.map { $0.base64EncodedString() },
                frontAudioExt:  card.frontAudioExt,
                backAudioData:  card.backAudioData.map  { $0.base64EncodedString() },
                backAudioExt:   card.backAudioExt
            )
        }

        let package = OboerPackage(
            version:    currentVersion,
            exportedAt: Date(),
            deck:       deckPackage,
            cards:      cardPackages
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy  = .iso8601
        encoder.outputFormatting      = [.prettyPrinted, .sortedKeys]

        do {
            return try encoder.encode(package)
        } catch {
            throw DeckShareError.encodingFailed(error.localizedDescription)
        }
    }

    // MARK: - Decode

    /// Decodes a raw JSON blob into an `OboerPackage`.
    /// Validates the version number; throws `DeckShareError` on failure.
    static func `import`(from data: Data) throws -> OboerPackage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let package: OboerPackage
        do {
            package = try decoder.decode(OboerPackage.self, from: data)
        } catch {
            throw DeckShareError.decodingFailed(error.localizedDescription)
        }

        guard package.version <= currentVersion else {
            throw DeckShareError.unsupportedVersion(package.version)
        }

        return package
    }

    // MARK: - Apply to SwiftData

    /// Creates a new `Deck` (and its cards) in `modelContext` from `package`.
    ///
    /// - A fresh UUID is assigned to each card; the original IDs from the package
    ///   are not reused to avoid collisions with existing cards.
    /// - All cards start as new (no FSRS history).
    /// - Returns the newly created `Deck`.
    @MainActor
    static func apply(package: OboerPackage, to modelContext: ModelContext) throws -> Deck {
        // Create deck
        let deck = Deck(
            name:      package.deck.name,
            colorHex:  package.deck.colorHex,
            iconName:  package.deck.iconName
        )
        modelContext.insert(deck)

        // Create cards
        for cp in package.cards {
            let cardType = CardType(rawValue: cp.cardType) ?? .basic

            let card = OboerCard(
                deck:         deck,
                cardType:     cardType,
                frontText:    cp.frontText,
                backText:     cp.backText,
                clozeText:    cp.clozeText,
                clozeOrdinal: cp.clozeOrdinal
            )

            // Decode base64 media back to Data
            card.frontImageData = cp.frontImageData.flatMap { Data(base64Encoded: $0) }
            card.backImageData  = cp.backImageData.flatMap  { Data(base64Encoded: $0) }
            card.frontAudioData = cp.frontAudioData.flatMap { Data(base64Encoded: $0) }
            card.frontAudioExt  = cp.frontAudioExt
            card.backAudioData  = cp.backAudioData.flatMap  { Data(base64Encoded: $0) }
            card.backAudioExt   = cp.backAudioExt
            card.tags           = cp.tags
            card.isReversed     = cp.isReversed

            modelContext.insert(card)
        }

        do {
            try modelContext.save()
        } catch {
            throw DeckShareError.saveFailed(error.localizedDescription)
        }

        return deck
    }

    // MARK: - Save to disk

    /// Writes the encoded JSON to `url`.
    /// Convenience wrapper around `export(deck:)` + `Data.write(to:)`.
    static func save(deck: Deck, to url: URL) throws {
        let data = try export(deck: deck)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw DeckShareError.saveFailed(error.localizedDescription)
        }
    }
}
