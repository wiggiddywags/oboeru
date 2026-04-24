import Foundation
import SwiftData

// CSVImporter parses a CSV/TSV file and creates OboerCards in the given deck.
//
// Robustness features
// ───────────────────
// • Auto-detects delimiter: comma, tab, semicolon, pipe
// • Encoding fallback: UTF-8 → UTF-8+BOM → Windows-1252 → Latin-1
// • Strips HTML tags; decodes HTML entities (Anki / Google Sheets exports)
// • Normalises whitespace (non-breaking spaces, collapsed runs, leading/trailing)
// • Flexible column names: see frontKeys / backKeys / clozeKeys below
// • Reversed columns detected ("Back, Front" → swapped automatically)
// • Extra columns (tags, notes, audio) silently ignored
// • Duplicate front-text flagged as warnings in preview
//
// Supported card formats
// ──────────────────────
// Basic (2+ columns):
//   Front,Back
//   What is the capital of France?,Paris
//
// Cloze (single column, or any cell with {{...}}):
//   Text
//   The {{capital}} of France is {{Paris}}.

// MARK: - Draft card

struct CSVDraftCard: Identifiable {
    var id = UUID()
    var front: String
    var back: String
    var cardType: CardType
    var isEnabled: Bool = true
    var sourceRow: Int       // 1-indexed CSV row; 0 = manually added

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

// MARK: - Importer

final class CSVImporter {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Column name vocabularies

    /// All recognised names for the "front / question" column.
    private let frontKeys = [
        "front", "question", "term", "word", "kanji", "hanzi",
        "prompt", "q", "stimulus", "target", "phrase", "sentence",
        "english", "native", "source",
    ]
    /// All recognised names for the "back / answer" column.
    private let backKeys = [
        "back", "answer", "definition", "meaning", "reading",
        "translation", "response", "a", "gloss", "explanation",
        "foreign", "target language", "pinyin", "furigana",
    ]
    /// All recognised names for a cloze-text column.
    private let clozeKeys = ["text", "cloze", "note", "card", "content"]

    // MARK: - Public API

    /// Parses `url` and returns draft cards **without** persisting anything.
    func parseOnly(from url: URL) async -> (cards: [CSVDraftCard], errors: [String]) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let raw = readString(from: url) else {
            return ([], ["Could not read file. Ensure it is a plain-text CSV/TSV (UTF-8, UTF-16, or Windows-1252)."])
        }

        let delimiter = detectDelimiter(in: raw)
        let rows      = parseCSV(raw, delimiter: delimiter)
        guard !rows.isEmpty else { return ([], ["File is empty."]) }

        let (format, colMap, dataRows) = detectFormat(rows, delimiter: delimiter)
        let headerOffset = rows.count - dataRows.count + 1
        var cards:  [CSVDraftCard] = []
        var errors: [String]       = []
        var seenFronts: Set<String> = []

        for (i, row) in dataRows.enumerated() {
            let rowNum = i + headerOffset
            // Skip entirely-blank rows
            guard row.contains(where: { !$0.trimmed.isEmpty }) else { continue }

            switch format {
            case .basic:
                let front = cleanCell(rawCell(row, col: colMap.frontIndex))
                let back  = cleanCell(rawCell(row, col: colMap.backIndex))
                guard !front.isEmpty else {
                    errors.append("Row \(rowNum): empty front — skipped")
                    continue
                }
                if seenFronts.contains(front) {
                    errors.append("Row \(rowNum): duplicate front text \"\(front.truncated(40))\"")
                }
                seenFronts.insert(front)
                cards.append(CSVDraftCard(front: front, back: back, cardType: .basic, sourceRow: rowNum))

            case .cloze:
                let text = cleanCell(rawCell(row, col: colMap.frontIndex))
                guard !text.isEmpty else {
                    errors.append("Row \(rowNum): empty text — skipped")
                    continue
                }
                guard ClozeParser.isValid(text) else {
                    errors.append("Row \(rowNum): no valid {{cloze}} markers — skipped")
                    continue
                }
                cards.append(CSVDraftCard(front: text, back: "", cardType: .cloze, sourceRow: rowNum))
            }
        }

        return (cards, errors)
    }

    /// Imports pre-approved draft cards into `deck`.
    func importDraftCards(_ cards: [CSVDraftCard], into deck: Deck) async -> CSVImportResult {
        var created = 0, skipped = 0
        var errors: [String] = []

        for draft in cards where draft.isEnabled {
            switch draft.cardType {
            case .basic:
                guard !draft.front.isEmpty else { skipped += 1; continue }
                modelContext.insert(OboerCard(deck: deck, cardType: .basic,
                                              frontText: draft.front, backText: draft.back))
                created += 1

            case .cloze:
                guard ClozeParser.isValid(draft.front) else { skipped += 1; continue }
                for sibling in ClozeParser.siblings(for: draft.front) {
                    modelContext.insert(OboerCard(
                        deck: deck, cardType: .cloze,
                        frontText: sibling.maskedText, backText: sibling.fullText,
                        clozeText: draft.front, clozeOrdinal: sibling.ordinal
                    ))
                    created += 1
                }
            }
        }

        try? modelContext.save()
        return CSVImportResult(created: created, skipped: skipped, errors: errors)
    }

    /// Legacy direct-import path (skips preview). Still used for the Anki fallback path.
    func importCSV(from url: URL, into deck: Deck) async -> CSVImportResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        guard let raw = readString(from: url) else {
            return CSVImportResult(created: 0, skipped: 0, errors: ["Could not read file."])
        }

        let delimiter = detectDelimiter(in: raw)
        let rows      = parseCSV(raw, delimiter: delimiter)
        guard !rows.isEmpty else {
            return CSVImportResult(created: 0, skipped: 0, errors: ["File is empty."])
        }

        let (format, colMap, dataRows) = detectFormat(rows, delimiter: delimiter)
        var created = 0, skipped = 0
        var errors: [String] = []

        for (i, row) in dataRows.enumerated() {
            guard row.contains(where: { !$0.trimmed.isEmpty }) else { continue }
            do {
                let ok = try await createCard(row: row, rowIndex: i + 2,
                                              format: format, colMap: colMap, deck: deck)
                if ok { created += 1 } else { skipped += 1 }
            } catch {
                errors.append("Row \(i + 2): \(error.localizedDescription)")
                skipped += 1
            }
        }

        try? modelContext.save()
        return CSVImportResult(created: created, skipped: skipped, errors: errors)
    }

    // MARK: - Column map

    struct ColumnMap {
        var frontIndex: Int? = nil
        var backIndex:  Int? = nil
        var isReversed: Bool = false
    }

    // MARK: - Format / delimiter detection

    enum CSVFormat { case basic, cloze }

    /// Scores each candidate delimiter by consistency across the first 10 non-empty lines.
    func detectDelimiter(in text: String) -> Character {
        let sample = String(text.prefix(8192))
        let lines  = sample.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(10)

        let candidates: [Character] = ["\t", ",", ";", "|"]
        var bestDelim: Character = ","
        var bestScore = -1

        for delim in candidates {
            let counts = lines.map { $0.filter { $0 == delim }.count }
            let nonZero = counts.filter { $0 > 0 }
            guard nonZero.count >= 2 else { continue }

            // Score: number of lines with this delimiter × minimum count per line,
            // boosted if the count is the same across all lines (very consistent).
            let minC = nonZero.min()!
            let maxC = nonZero.max()!
            let consistencyBonus = (minC == maxC) ? nonZero.count * 4 : 0
            let score = nonZero.count * minC + consistencyBonus
            if score > bestScore { bestScore = score; bestDelim = delim }
        }
        return bestDelim
    }

    /// Determines the card format and maps column indices.
    private func detectFormat(_ rows: [[String]], delimiter: Character) -> (CSVFormat, ColumnMap, [[String]]) {
        guard let firstRow = rows.first else { return (.basic, ColumnMap(), []) }

        // Score the first row as a header: matches known vocab, short, no {{}}
        let headerScore = firstRow.reduce(0) { score, cell in
            let c = cell.lowercased().trimmed
            let isKnown  = frontKeys.contains(c) || backKeys.contains(c) || clozeKeys.contains(c)
            let isShort  = c.count < 50
            let hasMarks = c.contains("{{")
            return score + (isKnown ? 3 : 0) + (isShort && !hasMarks ? 1 : 0)
        }
        let isHeader  = headerScore >= 2 || firstRow.allSatisfy { !$0.contains("{{") && $0.count < 50 }
        let headers   = isHeader ? firstRow.map { $0.lowercased().trimmed } : []
        let dataRows  = isHeader ? Array(rows.dropFirst()) : rows

        // Build column map from headers (or fall back to positional)
        var colMap = ColumnMap()
        if !headers.isEmpty {
            for (i, h) in headers.enumerated() {
                if frontKeys.contains(h)     { colMap.frontIndex = i }
                else if backKeys.contains(h) { colMap.backIndex  = i }
                else if clozeKeys.contains(h), colMap.frontIndex == nil { colMap.frontIndex = i }
            }
            // Detect reversed layout: back found before front
            if let b = colMap.backIndex, let f = colMap.frontIndex, b < f {
                swap(&colMap.frontIndex, &colMap.backIndex)
                colMap.isReversed = true
            }
        }
        // Positional fallback
        if colMap.frontIndex == nil { colMap.frontIndex = 0 }
        if colMap.backIndex  == nil, firstRow.count >= 2 { colMap.backIndex = 1 }

        // Decide format
        let effectiveCols = firstRow.count
        let hasClozeHeader = headers.contains(where: { clozeKeys.contains($0) })
        let hasClozeData   = dataRows.prefix(5).contains { row in
            row.first?.contains("{{") == true
        }

        if effectiveCols == 1 || hasClozeHeader || hasClozeData {
            return (.cloze, colMap, dataRows)
        }
        return (.basic, colMap, dataRows)
    }

    // MARK: - Card creation (legacy direct-import path)

    private func createCard(row: [String], rowIndex: Int, format: CSVFormat,
                            colMap: ColumnMap, deck: Deck) async throws -> Bool {
        guard row.contains(where: { !$0.trimmed.isEmpty }) else { return false }

        switch format {
        case .basic:
            let front = cleanCell(rawCell(row, col: colMap.frontIndex))
            let back  = cleanCell(rawCell(row, col: colMap.backIndex))
            guard !front.isEmpty else { return false }
            let card = OboerCard(deck: deck, cardType: .basic, frontText: front, backText: back)
            modelContext.insert(card)
            return true

        case .cloze:
            let text = cleanCell(rawCell(row, col: colMap.frontIndex))
            guard ClozeParser.isValid(text) else { return false }
            for sibling in ClozeParser.siblings(for: text) {
                modelContext.insert(OboerCard(
                    deck: deck, cardType: .cloze,
                    frontText: sibling.maskedText, backText: sibling.fullText,
                    clozeText: text, clozeOrdinal: sibling.ordinal
                ))
            }
            return true
        }
    }

    // MARK: - Image downloading

    private func downloadImage(from urlString: String) async -> Data? {
        guard !urlString.isEmpty else { return nil }
        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
            guard let url = URL(string: urlString) else { return nil }
            return try? await URLSession.shared.data(from: url).0
        }
        let fileURL: URL = urlString.hasPrefix("file://")
            ? (URL(string: urlString) ?? URL(fileURLWithPath: urlString))
            : URL(fileURLWithPath: urlString)
        return try? Data(contentsOf: fileURL)
    }

    // MARK: - RFC 4180 CSV parser (delimiter-aware)

    func parseCSV(_ text: String, delimiter: Character = ",") -> [[String]] {
        var rows:         [[String]] = []
        var currentRow:   [String]   = []
        var currentField: String     = ""
        var inQuotes = false
        var i = text.startIndex

        while i < text.endIndex {
            let c = text[i]

            if inQuotes {
                if c == "\"" {
                    let next = text.index(after: i)
                    if next < text.endIndex && text[next] == "\"" {
                        // Escaped quote → literal "
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
                } else if c == delimiter {
                    currentRow.append(currentField)
                    currentField = ""
                } else if c == "\n" || c == "\r" {
                    currentRow.append(currentField)
                    currentField = ""
                    if currentRow.contains(where: { !$0.isEmpty }) {
                        rows.append(currentRow)
                    }
                    currentRow = []
                    // Consume \r\n as one newline
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

        currentRow.append(currentField)
        if currentRow.contains(where: { !$0.isEmpty }) { rows.append(currentRow) }
        return rows
    }

    // MARK: - Cell cleaning

    /// Returns the raw string at `col`, or "" if out of bounds.
    private func rawCell(_ row: [String], col: Int?) -> String {
        guard let col, col < row.count else { return "" }
        return row[col]
    }

    /// Strips HTML, decodes entities, normalises whitespace.
    func cleanCell(_ raw: String) -> String {
        var s = raw

        // Replace block-level tags with newlines before stripping
        let blockTags = ["</p>", "<br>", "<br/>", "<br />", "</div>", "</li>", "</tr>"]
        for tag in blockTags {
            s = s.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }

        // Strip all remaining HTML tags
        if s.contains("<") {
            s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }

        // Decode HTML entities
        s = decodeHTMLEntities(s)

        // Replace non-breaking space and other odd Unicode spaces with regular space
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ")  // NBSP
        s = s.replacingOccurrences(of: "\u{2009}", with: " ")  // thin space
        s = s.replacingOccurrences(of: "\u{200B}", with: "")   // zero-width space

        // Collapse multiple spaces within each line; preserve newlines
        let lines = s.components(separatedBy: "\n").map { line -> String in
            line.components(separatedBy: " ").filter { !$0.isEmpty }.joined(separator: " ")
        }
        s = lines.joined(separator: "\n")

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTMLEntities(_ input: String) -> String {
        var s = input
        // Named entities (case-insensitive)
        let named: [(String, String)] = [
            ("&amp;",   "&"),  ("&lt;",    "<"),  ("&gt;",   ">"),
            ("&quot;",  "\""), ("&apos;",  "'"),  ("&#39;",  "'"),
            ("&nbsp;",  " "),  ("&hellip;","…"),  ("&mdash;","—"),
            ("&ndash;", "–"),  ("&laquo;", "«"),  ("&raquo;","»"),
            ("&lsquo;", "'"),  ("&rsquo;", "'"),  ("&ldquo;","\u{201C}"),
            ("&rdquo;", "\u{201D}"),               ("&bull;", "•"),
        ]
        for (entity, char) in named {
            s = s.replacingOccurrences(of: entity, with: char, options: .caseInsensitive)
        }
        // Numeric decimal entities: &#NNN;
        if s.contains("&#") {
            if let re = try? NSRegularExpression(pattern: #"&#(\d+);"#) {
                let ns = NSMutableString(string: s)
                let matches = re.matches(in: s, range: NSRange(s.startIndex..., in: s))
                for match in matches.reversed() {
                    if let numRange = Range(match.range(at: 1), in: s),
                       let code = UInt32(s[numRange]),
                       let scalar = Unicode.Scalar(code) {
                        ns.replaceCharacters(in: match.range, with: String(Character(scalar)))
                    }
                }
                s = ns as String
            }
        }
        // Numeric hex entities: &#xHHH;
        if s.contains("&#x") || s.contains("&#X") {
            if let re = try? NSRegularExpression(pattern: #"&#[xX]([0-9a-fA-F]+);"#) {
                let ns = NSMutableString(string: s)
                let matches = re.matches(in: s, range: NSRange(s.startIndex..., in: s))
                for match in matches.reversed() {
                    if let hexRange = Range(match.range(at: 1), in: s),
                       let code = UInt32(s[hexRange], radix: 16),
                       let scalar = Unicode.Scalar(code) {
                        ns.replaceCharacters(in: match.range, with: String(Character(scalar)))
                    }
                }
                s = ns as String
            }
        }
        return s
    }

    // MARK: - Encoding

    private func readString(from url: URL) -> String? {
        // 1. Plain UTF-8
        if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        guard let data = try? Data(contentsOf: url) else { return nil }
        // 2. UTF-8 with BOM stripped
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        let payload = data.prefix(3).elementsEqual(bom) ? Data(data.dropFirst(3)) : data
        if let s = String(data: payload, encoding: .utf8)           { return s }
        // 3. UTF-16 (some Excel exports)
        if let s = String(data: data, encoding: .utf16)             { return s }
        // 4. Windows-1252 / Latin-1 (legacy Excel / Numbers)
        if let s = String(data: payload, encoding: .windowsCP1252)  { return s }
        if let s = String(data: payload, encoding: .isoLatin1)      { return s }
        return nil
    }
}

// MARK: - String helpers

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    func truncated(_ max: Int) -> String {
        count <= max ? self : String(prefix(max)) + "…"
    }
}

