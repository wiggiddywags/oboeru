import Foundation
import SwiftData

// CSVImporter parses a CSV file and creates OboerCards in the given deck.
//
// Supported formats:
//
//   Basic (2+ columns):
//     Front,Back[,Front Image,Back Image]
//     What is the capital of France?,Paris
//     What color is the sky?,Blue,https://example.com/sky.jpg
//
//   Cloze (1 column, or "Text"/"text" header, or any cell containing {{}}):
//     Text
//     The {{capital::city}} of France is {{Paris}}.
//
// Image columns accept:
//   - https:// or http:// URL  → downloaded during import
//   - file:// URL or absolute path → read from disk
//   - Empty → no image

// MARK: - Draft card (used by preview sheet before committing)

struct CSVDraftCard: Identifiable {
    var id = UUID()
    var front: String
    var back: String
    var cardType: CardType
    var isEnabled: Bool = true
    var sourceRow: Int       // 1-indexed CSV row, 0 = manually added

    init(front: String, back: String, cardType: CardType, sourceRow: Int = 0) {
        self.front = front
        self.back = back
        self.cardType = cardType
        self.sourceRow = sourceRow
    }
}

struct CSVImportResult {
    let created: Int
    let skipped: Int
    let errors: [String]
}

final class CSVImporter {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public

    /// Parses `url` and returns draft cards **without** persisting anything.
    /// Used by the preview sheet so the user can review/edit before committing.
    func parseOnly(from url: URL) async -> (cards: [CSVDraftCard], errors: [String]) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return ([], ["Could not read file."])
        }

        let rows = parseCSV(raw)
        guard !rows.isEmpty else { return ([], ["File is empty."]) }

        let (format, headers, dataRows) = detectFormat(rows)
        let headerOffset = rows.count - dataRows.count + 1
        var cards: [CSVDraftCard] = []
        var errors: [String] = []

        for (i, row) in dataRows.enumerated() {
            guard !row.isEmpty, !row[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let rowNum = i + headerOffset

            switch format {
            case .basic:
                let front = cell(row, index: 0, headers: headers, keys: ["front", "question", "term"]).trimmed
                let back  = cell(row, index: 1, headers: headers, keys: ["back", "answer", "definition"]).trimmed
                if front.isEmpty {
                    errors.append("Row \(rowNum): empty front — skipped")
                    continue
                }
                cards.append(CSVDraftCard(front: front, back: back, cardType: .basic, sourceRow: rowNum))

            case .cloze:
                let text = row[0].trimmed
                if !ClozeParser.isValid(text) {
                    errors.append("Row \(rowNum): no valid {{cloze}} markers — skipped")
                    continue
                }
                cards.append(CSVDraftCard(front: text, back: "", cardType: .cloze, sourceRow: rowNum))
            }
        }

        return (cards, errors)
    }

    /// Imports a set of already-approved draft cards into `deck`.
    /// Called by the preview sheet after the user clicks "Import".
    func importDraftCards(_ cards: [CSVDraftCard], into deck: Deck) async -> CSVImportResult {
        var created = 0
        var skipped = 0
        var errors: [String] = []

        for draft in cards where draft.isEnabled {
            switch draft.cardType {
            case .basic:
                guard !draft.front.isEmpty else { skipped += 1; continue }
                let card = OboerCard(deck: deck, cardType: .basic,
                                     frontText: draft.front, backText: draft.back)
                modelContext.insert(card)
                created += 1

            case .cloze:
                guard ClozeParser.isValid(draft.front) else { skipped += 1; continue }
                for sibling in ClozeParser.siblings(for: draft.front) {
                    let card = OboerCard(
                        deck: deck, cardType: .cloze,
                        frontText: sibling.maskedText, backText: sibling.fullText,
                        clozeText: draft.front, clozeOrdinal: sibling.ordinal
                    )
                    modelContext.insert(card)
                    created += 1
                }
            }
        }

        try? modelContext.save()
        return CSVImportResult(created: created, skipped: skipped, errors: errors)
    }

    /// Parses `url` and inserts cards into `deck`. Awaitable so image downloads don't block UI.
    func importCSV(from url: URL, into deck: Deck) async -> CSVImportResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return CSVImportResult(created: 0, skipped: 0, errors: ["Could not read file."])
        }

        let rows = parseCSV(raw)
        guard !rows.isEmpty else {
            return CSVImportResult(created: 0, skipped: 0, errors: ["File is empty."])
        }

        let (format, headers, dataRows) = detectFormat(rows)
        var created = 0
        var skipped = 0
        var errors: [String] = []

        for (i, row) in dataRows.enumerated() {
            do {
                let didCreate = try await createCard(
                    row: row, rowIndex: i + 2, format: format,
                    headers: headers, deck: deck
                )
                if didCreate { created += 1 } else { skipped += 1 }
            } catch {
                errors.append("Row \(i + 2): \(error.localizedDescription)")
                skipped += 1
            }
        }

        try? modelContext.save()
        return CSVImportResult(created: created, skipped: skipped, errors: errors)
    }

    // MARK: - Format detection

    enum CSVFormat { case basic, cloze }

    private func detectFormat(_ rows: [[String]]) -> (CSVFormat, [String], [[String]]) {
        guard let firstRow = rows.first else { return (.basic, [], []) }

        // Check if first row looks like a header (no {{}} and not obviously content)
        let looksLikeHeader = firstRow.allSatisfy { cell in
            !cell.contains("{{") && cell.count < 60
        }

        let headers = looksLikeHeader ? firstRow.map { $0.lowercased() } : []
        let dataRows = looksLikeHeader ? Array(rows.dropFirst()) : rows

        // Cloze if: single column named "text", OR any data cell contains {{}}
        let isSingleColumn = (firstRow.count == 1) || (headers.count == 1 && headers[0] == "text")
        let hasClozeMarkers = dataRows.prefix(5).contains { row in
            row.first?.contains("{{") == true
        }

        if isSingleColumn || hasClozeMarkers {
            return (.cloze, headers, dataRows)
        }

        return (.basic, headers, dataRows)
    }

    // MARK: - Card creation

    private func createCard(
        row: [String], rowIndex: Int, format: CSVFormat,
        headers: [String], deck: Deck
    ) async throws -> Bool {
        guard !row.isEmpty, !row[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        switch format {
        case .basic:
            return try await createBasicCard(row: row, headers: headers, deck: deck)
        case .cloze:
            return try await createClozeCard(row: row, headers: headers, deck: deck)
        }
    }

    private func createBasicCard(row: [String], headers: [String], deck: Deck) async throws -> Bool {
        let front = cell(row, index: 0, headers: headers, keys: ["front", "question", "term"]).trimmed
        let back  = cell(row, index: 1, headers: headers, keys: ["back", "answer", "definition"]).trimmed
        guard !front.isEmpty else { return false }

        let frontImageURL = cell(row, index: 2, headers: headers, keys: ["front image", "front_image", "image"]).trimmed
        let backImageURL  = cell(row, index: 3, headers: headers, keys: ["back image",  "back_image"]).trimmed

        let card = OboerCard(deck: deck, cardType: .basic, frontText: front, backText: back)
        card.frontImageData = await downloadImage(from: frontImageURL)
        card.backImageData  = await downloadImage(from: backImageURL)
        modelContext.insert(card)
        return true
    }

    private func createClozeCard(row: [String], headers: [String], deck: Deck) async throws -> Bool {
        let text = row[0].trimmed
        guard ClozeParser.isValid(text) else { return false }

        let imageURL = cell(row, index: 1, headers: headers, keys: ["image", "front image", "front_image"]).trimmed
        let imageData = await downloadImage(from: imageURL)

        for sibling in ClozeParser.siblings(for: text) {
            let card = OboerCard(
                deck: deck, cardType: .cloze,
                frontText: sibling.maskedText, backText: sibling.fullText,
                clozeText: text, clozeOrdinal: sibling.ordinal
            )
            card.frontImageData = imageData
            modelContext.insert(card)
        }
        return true
    }

    // MARK: - Image downloading

    private func downloadImage(from urlString: String) async -> Data? {
        guard !urlString.isEmpty else { return nil }

        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            guard let url = URL(string: urlString) else { return nil }
            return try? await URLSession.shared.data(from: url).0
        }

        // Local file path
        var fileURL: URL
        if urlString.hasPrefix("file://") {
            fileURL = URL(string: urlString) ?? URL(fileURLWithPath: urlString)
        } else {
            fileURL = URL(fileURLWithPath: urlString)
        }
        return try? Data(contentsOf: fileURL)
    }

    // MARK: - CSV parsing (RFC 4180 compliant)

    func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]

            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\"" {
                        currentField.append("\"")
                        i = text.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(c)
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                } else if c == "," {
                    currentRow.append(currentField)
                    currentField = ""
                } else if c == "\n" || c == "\r" {
                    currentRow.append(currentField)
                    currentField = ""
                    if !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    // Skip \r\n
                    let next = text.index(after: i)
                    if c == "\r", next < text.endIndex, text[next] == "\n" {
                        i = next
                    }
                } else {
                    currentField.append(c)
                }
            }
            i = text.index(after: i)
        }

        // Final field/row
        currentRow.append(currentField)
        if !currentRow.allSatisfy({ $0.isEmpty }) { rows.append(currentRow) }

        return rows
    }

    // MARK: - Helpers

    /// Gets a cell value by index or by matching header names.
    private func cell(_ row: [String], index: Int, headers: [String], keys: [String]) -> String {
        for key in keys {
            if let hi = headers.firstIndex(of: key), hi < row.count {
                return row[hi]
            }
        }
        return index < row.count ? row[index] : ""
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
