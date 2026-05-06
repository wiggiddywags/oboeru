import Foundation
import SwiftData
import SQLite3

// AnkiImporter reads an .apkg file (ZIP containing an SQLite collection) and
// returns a structured array of AnkiImportDeck values ready for preview / insertion.
//
// .apkg structure:
//   collection.anki21  — SQLite database (newer Anki versions, preferred)
//   collection.anki2   — SQLite database (legacy)
//   media              — JSON mapping "0","1",… → original filenames
//   0, 1, 2, …         — media files (images, audio)

// MARK: - Public result types

struct AnkiImportDeck {
    let name: String
    let colorHex: String      // randomly assigned from a palette
    var cards: [AnkiImportCard]
}

struct AnkiImportCard {
    let cardType: CardType
    let frontText: String
    let backText: String
    let clozeText: String?    // only populated for .cloze cards
    let tags: [String]
}

enum AnkiImportError: LocalizedError {
    case cannotReadFile(String)
    case unzipFailed(String)
    case noDatabaseFound
    case cannotOpenDatabase
    case cannotReadMetadata

    var errorDescription: String? {
        switch self {
        case .cannotReadFile(let msg):  return "Cannot read file: \(msg)"
        case .unzipFailed(let msg):     return "Unzip failed: \(msg)"
        case .noDatabaseFound:          return "No Anki collection database found in .apkg file."
        case .cannotOpenDatabase:       return "Could not open the collection database."
        case .cannotReadMetadata:       return "Could not read collection metadata from the database."
        }
    }
}

// MARK: - Importer

enum AnkiImporter {

    // MARK: - Palette

    private static let deckColors: [String] = [
        "#5E9CF0", "#F0825E", "#5ECC8A", "#C45EF0",
        "#F0C75E", "#5ECEF0", "#F05E8C", "#8CF05E",
    ]

    // MARK: - Public entry point

    /// Parses an `.apkg` file and returns an array of decks with their cards.
    /// Throws `AnkiImportError` on failure. Does **not** touch SwiftData.
    static func `import`(from url: URL) throws -> [AnkiImportDeck] {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try unzip(apkg: url, to: tempDir)

        let dbURL = findDatabase(in: tempDir)
        guard let dbURL else { throw AnkiImportError.noDatabaseFound }

        var db: OpaquePointer?
        let opened = sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil)
        guard opened == SQLITE_OK, let db else { throw AnkiImportError.cannotOpenDatabase }
        defer { sqlite3_close(db) }

        guard let (models, deckIdToName) = parseCol(db: db) else {
            throw AnkiImportError.cannotReadMetadata
        }

        let noteDeckMap = parseNoteDeckMap(db: db)
        let cardsByDeckName = parseNotes(
            db: db,
            models: models,
            noteDeckMap: noteDeckMap,
            deckIdToName: deckIdToName
        )

        return buildDecks(from: cardsByDeckName, deckIdToName: deckIdToName)
    }

    // MARK: - Internal helpers

    // Unzips `apkg` into `destination` using the system /usr/bin/unzip binary.
    private static func unzip(apkg: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", apkg.path, "-d", destination.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()   // suppress stdout

        do {
            try process.run()
        } catch {
            throw AnkiImportError.unzipFailed(error.localizedDescription)
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "unknown error"
            throw AnkiImportError.unzipFailed(errMsg)
        }
    }

    // Returns the URL of the collection database inside `dir`, preferring .anki21.
    private static func findDatabase(in dir: URL) -> URL? {
        let candidates = ["collection.anki21", "collection.anki2"]
        for name in candidates {
            let url = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    // MARK: - Internal SQLite model types

    private enum AnkiModelType { case basic, cloze }

    private struct AnkiModel {
        let id: Int64
        let name: String
        let type: AnkiModelType
        let fieldNames: [String]
    }

    // MARK: - col table parsing

    /// Reads `models` and `decks` JSON from the single-row `col` table.
    /// Returns (modelId → AnkiModel, deckId → deckName). Skips the built-in "Default" deck.
    private static func parseCol(db: OpaquePointer) -> ([Int64: AnkiModel], [Int64: String])? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT models, decks FROM col LIMIT 1", -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let modelsJSON = columnString(stmt, col: 0)
        let decksJSON  = columnString(stmt, col: 1)

        let models = parseModelsJSON(modelsJSON)
        let decks  = parseDecksJSON(decksJSON)
        return (models, decks)
    }

    private static func parseModelsJSON(_ json: String) -> [Int64: AnkiModel] {
        guard let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        var result: [Int64: AnkiModel] = [:]
        for (key, value) in obj {
            guard let id   = Int64(key),
                  let dict = value as? [String: Any]
            else { continue }

            let name     = dict["name"] as? String ?? "Untitled"
            let typeInt  = dict["type"] as? Int ?? 0
            let mType: AnkiModelType = typeInt == 1 ? .cloze : .basic
            let flds     = (dict["flds"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            result[id]   = AnkiModel(id: id, name: name, type: mType, fieldNames: flds)
        }
        return result
    }

    /// Parses the decks JSON. Skips the entry whose name is exactly "Default".
    private static func parseDecksJSON(_ json: String) -> [Int64: String] {
        guard let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        var result: [Int64: String] = [:]
        for (key, value) in obj {
            guard let id   = Int64(key),
                  let dict = value as? [String: Any],
                  let name = dict["name"] as? String
            else { continue }
            if name == "Default" { continue }
            result[id] = name
        }
        // Fallback: if all decks were named "Default", keep the first one renamed.
        if result.isEmpty {
            for (key, value) in obj {
                if let id   = Int64(key),
                   let dict = value as? [String: Any] {
                    result[id] = dict["name"] as? String ?? "Imported"
                    break
                }
            }
        }
        return result
    }

    // MARK: - cards table — note → deck mapping

    /// Reads the `cards` table and returns a map of noteId → deckId.
    /// When a note has multiple cards (cloze), only the first encountered is used.
    private static func parseNoteDeckMap(db: OpaquePointer) -> [Int64: Int64] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT nid, did FROM cards ORDER BY ord ASC", -1, &stmt, nil) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_finalize(stmt) }

        var map: [Int64: Int64] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let nid = sqlite3_column_int64(stmt, 0)
            let did = sqlite3_column_int64(stmt, 1)
            if map[nid] == nil { map[nid] = did }
        }
        return map
    }

    // MARK: - notes table parsing

    /// Reads the `notes` table, maps each note to a deck name, converts Anki cloze
    /// syntax, strips HTML, and returns a dictionary of deckName → [AnkiImportCard].
    private static func parseNotes(
        db: OpaquePointer,
        models: [Int64: AnkiModel],
        noteDeckMap: [Int64: Int64],
        deckIdToName: [Int64: String]
    ) -> [String: [AnkiImportCard]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id, mid, flds, tags FROM notes", -1, &stmt, nil) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_finalize(stmt) }

        // Determine a fallback deck name.
        // If there's exactly one non-Default deck, assign orphaned notes there.
        // Otherwise use a synthetic "Imported" deck.
        let nonDefaultNames = Array(deckIdToName.values)
        let fallbackDeckName: String = nonDefaultNames.count == 1 ? nonDefaultNames[0] : "Imported"

        var result: [String: [AnkiImportCard]] = [:]

        while sqlite3_step(stmt) == SQLITE_ROW {
            let noteId   = sqlite3_column_int64(stmt, 0)
            let modelId  = sqlite3_column_int64(stmt, 1)
            let fldsRaw  = columnString(stmt, col: 2)
            let tagsRaw  = columnString(stmt, col: 3)

            guard let model = models[modelId] else { continue }

            // \u{1f} is Anki's field separator (ASCII Unit Separator = 0x1F)
            let fields = fldsRaw.components(separatedBy: "\u{1f}")
            let tags   = tagsRaw
                .components(separatedBy: .whitespaces)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            // Determine deck name for this note
            let deckName: String
            if let did = noteDeckMap[noteId], let name = deckIdToName[did] {
                deckName = name
            } else {
                deckName = fallbackDeckName
            }

            let cards: [AnkiImportCard]
            switch model.type {
            case .basic:
                guard let card = makeBasicCard(fields: fields, tags: tags) else { continue }
                cards = [card]
            case .cloze:
                cards = makeClozeCards(fields: fields, tags: tags)
                guard !cards.isEmpty else { continue }
            }

            result[deckName, default: []].append(contentsOf: cards)
        }

        return result
    }

    private static func makeBasicCard(fields: [String], tags: [String]) -> AnkiImportCard? {
        let front = stripHTML(fields.count > 0 ? fields[0] : "")
        let back  = stripHTML(fields.count > 1 ? fields[1] : "")
        guard !front.isEmpty else { return nil }
        return AnkiImportCard(cardType: .basic, frontText: front, backText: back,
                              clozeText: nil, tags: tags)
    }

    private static func makeClozeCards(fields: [String], tags: [String]) -> [AnkiImportCard] {
        let rawField = fields.count > 0 ? fields[0] : ""
        // Convert Anki cloze syntax ({{c1::answer}}) to Oboeru syntax ({{answer}})
        let converted = convertAnkiCloze(stripHTML(rawField))
        guard ClozeParser.isValid(converted) else { return [] }

        // Each sibling becomes one import card with front = masked, back = full
        return ClozeParser.siblings(for: converted).map { sibling in
            AnkiImportCard(
                cardType: .cloze,
                frontText: sibling.maskedText,
                backText: sibling.fullText,
                clozeText: converted,
                tags: tags
            )
        }
    }

    // MARK: - Deck assembly

    private static func buildDecks(
        from cardsByDeckName: [String: [AnkiImportCard]],
        deckIdToName: [Int64: String]
    ) -> [AnkiImportDeck] {
        // Preserve deck order: known deck names first (in id order), then any extras.
        var orderedNames: [String] = deckIdToName
            .sorted { $0.key < $1.key }
            .map { $0.value }
        for name in cardsByDeckName.keys where !orderedNames.contains(name) {
            orderedNames.append(name)
        }

        return orderedNames.enumerated().compactMap { (index, name) in
            guard let cards = cardsByDeckName[name], !cards.isEmpty else { return nil }
            let color = deckColors[index % deckColors.count]
            return AnkiImportDeck(name: name, colorHex: color, cards: cards)
        }
    }

    // MARK: - Cloze conversion

    /// Converts Anki cloze syntax to Oboeru cloze syntax.
    ///
    /// Anki:   `{{c1::answer}}` or `{{c1::answer::hint}}`
    /// Oboeru: `{{answer}}`     or `{{answer::hint}}`
    ///
    /// Multiple cloze numbers (c1, c2, …) are all stripped; each gap becomes
    /// an independent `{{…}}` marker and Oboeru's parser assigns ordinals sequentially.
    static func convertAnkiCloze(_ text: String) -> String {
        // Pattern: {{cN::answer}} or {{cN::answer::hint}}
        guard let regex = try? NSRegularExpression(
            pattern: #"\{\{c\d+::([^}:]+)(?:::([^}]*))?\}\}"#,
            options: []
        ) else { return text }

        let nsText = text as NSString
        let range  = NSRange(location: 0, length: nsText.length)
        let result = NSMutableString(string: text)
        let matches = regex.matches(in: text, range: range)

        // Replace in reverse order to preserve range validity
        for match in matches.reversed() {
            let answerRange = match.range(at: 1)
            let hintRange   = match.range(at: 2)

            let answer = answerRange.location != NSNotFound
                ? nsText.substring(with: answerRange)
                : ""
            let hint: String? = hintRange.location != NSNotFound && hintRange.length > 0
                ? nsText.substring(with: hintRange)
                : nil

            let replacement: String
            if let hint {
                replacement = "{{\(answer)::\(hint)}}"
            } else {
                replacement = "{{\(answer)}}"
            }
            result.replaceCharacters(in: match.range, with: replacement)
        }
        return result as String
    }

    // MARK: - HTML stripping

    /// Removes HTML tags and decodes common entities including numeric ones.
    static func stripHTML(_ html: String) -> String {
        var text = html

        // Remove <img> tags entirely (no media in this importer)
        text = text.replacingOccurrences(of: #"<img[^>]*>"#, with: "", options: .regularExpression)
        // Replace block-level tags with newlines
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"</?(?:div|p|li|tr)[^>]*>"#, with: "\n", options: .regularExpression)
        // Strip all remaining HTML tags
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)

        // Named entities
        let namedEntities: [(String, String)] = [
            ("&amp;",   "&"),  ("&lt;",  "<"),  ("&gt;",  ">"),
            ("&quot;",  "\""), ("&apos;","'"),  ("&#39;", "'"),
            ("&nbsp;",  " "),  ("&mdash;","—"), ("&ndash;","–"),
            ("&hellip;","…"),  ("&bull;","•"),
        ]
        for (entity, char) in namedEntities {
            text = text.replacingOccurrences(of: entity, with: char, options: .caseInsensitive)
        }

        // Numeric decimal: &#NNN;
        if text.contains("&#"), let re = try? NSRegularExpression(pattern: #"&#(\d+);"#) {
            let ns = NSMutableString(string: text)
            for match in re.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                if let r = Range(match.range(at: 1), in: text),
                   let code = UInt32(text[r]),
                   let scalar = Unicode.Scalar(code) {
                    ns.replaceCharacters(in: match.range, with: String(Character(scalar)))
                }
            }
            text = ns as String
        }

        // Numeric hex: &#xNNN;
        if text.contains("&#x") || text.contains("&#X"),
           let re = try? NSRegularExpression(pattern: #"&#[xX]([0-9a-fA-F]+);"#) {
            let ns = NSMutableString(string: text)
            for match in re.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                if let r = Range(match.range(at: 1), in: text),
                   let code = UInt32(text[r], radix: 16),
                   let scalar = Unicode.Scalar(code) {
                    ns.replaceCharacters(in: match.range, with: String(Character(scalar)))
                }
            }
            text = ns as String
        }

        // Normalise whitespace
        text = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")   // NBSP
            .replacingOccurrences(of: "\u{200B}", with: "")    // zero-width space
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - SQLite helper

    private static func columnString(_ stmt: OpaquePointer?, col: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: ptr)
    }
}
