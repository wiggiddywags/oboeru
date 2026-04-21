import Foundation
import SwiftData
import SQLite3
import ZipFoundation

// AnkiImporter reads an .apkg file (ZIP containing an SQLite collection) and
// creates matching Oboeru decks + cards, preserving scheduling state where possible.
//
// .apkg structure:
//   collection.anki2  — SQLite database (main)
//   collection.anki21 — SQLite database (newer Anki versions, preferred)
//   media             — JSON mapping "0","1",… → original filenames
//   0, 1, 2, …        — media files (images, audio)

struct AnkiImportResult {
    let decksCreated: Int
    let cardsCreated: Int
    let cardsSkipped: Int
    let errors: [String]
}

final class AnkiImporter {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public

    func importAPKG(from url: URL) async -> AnkiImportResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // Unzip to a temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try FileManager.default.unzipItem(at: url, to: tempDir)
        } catch {
            return AnkiImportResult(decksCreated: 0, cardsCreated: 0, cardsSkipped: 0,
                                    errors: ["Could not unzip file: \(error.localizedDescription)"])
        }

        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Prefer newer .anki21 format
        let dbPath = tempDir.appendingPathComponent("collection.anki21").path.fileExists
            ? tempDir.appendingPathComponent("collection.anki21").path
            : tempDir.appendingPathComponent("collection.anki2").path

        guard FileManager.default.fileExists(atPath: dbPath) else {
            return AnkiImportResult(decksCreated: 0, cardsCreated: 0, cardsSkipped: 0,
                                    errors: ["No collection database found in .apkg file."])
        }

        // Parse media map
        let mediaMap = parseMediaMap(tempDir: tempDir)

        return await importFromDatabase(dbPath: dbPath, tempDir: tempDir, mediaMap: mediaMap)
    }

    // MARK: - Database import

    private func importFromDatabase(
        dbPath: String, tempDir: URL, mediaMap: [String: String]
    ) async -> AnkiImportResult {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return AnkiImportResult(decksCreated: 0, cardsCreated: 0, cardsSkipped: 0,
                                    errors: ["Could not open collection database."])
        }
        defer { sqlite3_close(db) }

        // Load models and decks from the col table
        guard let (models, ankiDecks) = readCollectionMeta(db: db) else {
            return AnkiImportResult(decksCreated: 0, cardsCreated: 0, cardsSkipped: 0,
                                    errors: ["Could not read collection metadata."])
        }

        // Create Oboeru decks (keyed by Anki deck id)
        var deckMap: [Int64: Deck] = [:]
        for (deckID, ankiDeck) in ankiDecks {
            let name = ankiDeck.name.components(separatedBy: "::").last ?? ankiDeck.name
            let deck = Deck(name: name)
            modelContext.insert(deck)
            deckMap[deckID] = deck
        }

        // Read scheduling info from cards table (keyed by note id)
        let cardSchedules = readCardSchedules(db: db)

        // Read and create notes
        var created = 0
        var skipped = 0
        var errors: [String] = []

        let notes = readNotes(db: db)
        for note in notes {
            guard let model = models[note.modelID] else { skipped += 1; continue }

            // Find the deck for this note via its first card
            let schedule = cardSchedules[note.id]
            let deckID = schedule?.deckID ?? ankiDecks.keys.first ?? 0
            guard let deck = deckMap[deckID] ?? deckMap.values.first else { skipped += 1; continue }

            do {
                let count = try createCards(
                    from: note, model: model, schedule: schedule,
                    deck: deck, tempDir: tempDir, mediaMap: mediaMap
                )
                created += count
            } catch {
                errors.append("Note \(note.id): \(error.localizedDescription)")
                skipped += 1
            }
        }

        try? modelContext.save()

        return AnkiImportResult(
            decksCreated: deckMap.count,
            cardsCreated: created,
            cardsSkipped: skipped,
            errors: errors
        )
    }

    // MARK: - Card creation from note

    private func createCards(
        from note: AnkiNote, model: AnkiModel, schedule: AnkiCardSchedule?,
        deck: Deck, tempDir: URL, mediaMap: [String: String]
    ) throws -> Int {
        let fields = note.fields.components(separatedBy: "\u{1f}")  // \x1f separator
        guard !fields.isEmpty else { return 0 }

        switch model.type {
        case .cloze:
            let rawText = stripHTML(fields[0])
            guard ClozeParser.isValid(rawText) else { return 0 }
            var count = 0
            for sibling in ClozeParser.siblings(for: rawText) {
                let card = OboerCard(
                    deck: deck, cardType: .cloze,
                    frontText: sibling.maskedText, backText: sibling.fullText,
                    clozeText: rawText, clozeOrdinal: sibling.ordinal
                )
                applySchedule(schedule, to: card)
                modelContext.insert(card)
                count += 1
            }
            return count

        case .basic:
            let front = fields.count > 0 ? stripHTML(fields[0]) : ""
            let back  = fields.count > 1 ? stripHTML(fields[1]) : ""
            guard !front.isEmpty else { return 0 }

            let card = OboerCard(deck: deck, cardType: .basic, frontText: front, backText: back)

            // Try to load the first image tag from front/back fields as card image
            if fields.count > 0 {
                card.frontImageData = extractImage(from: fields[0], tempDir: tempDir, mediaMap: mediaMap)
            }
            if fields.count > 1 {
                card.backImageData = extractImage(from: fields[1], tempDir: tempDir, mediaMap: mediaMap)
            }

            applySchedule(schedule, to: card)
            modelContext.insert(card)
            return 1
        }
    }

    // MARK: - Schedule mapping (SM-2 → FSRS approximation)

    private func applySchedule(_ schedule: AnkiCardSchedule?, to card: OboerCard) {
        guard let s = schedule, s.reps > 0 else { return }

        // Map Anki card type to FSRS state
        switch s.cardType {
        case 0: card.fsrsStateRaw = OboerCardState.new.rawValue
        case 1: card.fsrsStateRaw = OboerCardState.learning.rawValue
        case 2: card.fsrsStateRaw = OboerCardState.review.rawValue
        case 3: card.fsrsStateRaw = OboerCardState.relearning.rawValue
        default: break
        }

        // Anki interval is in days (positive) — approximate FSRS stability
        if s.interval > 0 {
            card.fsrsStability = Double(s.interval)
            card.fsrsScheduledDays = Double(s.interval)
            card.fsrsDifficulty = ankiEaseToFSRSDifficulty(s.easeFactor)
            card.fsrsReps = s.reps
            card.fsrsLapses = s.lapses

            // Set due date based on Anki's due value
            // Anki due = days since collection creation for review cards
            let daysUntilDue = max(0, s.interval - 1)
            card.fsrsDue = Calendar.current.date(byAdding: .day, value: daysUntilDue, to: Date()) ?? Date()
            card.fsrsLastReview = Date()
        }
    }

    /// Maps Anki ease factor (default 2500 = 2.5) to FSRS difficulty (1–10).
    /// Higher ease → lower difficulty. Anki ease range is typically 1300–3500.
    private func ankiEaseToFSRSDifficulty(_ easeFactor: Int) -> Double {
        let ease = Double(easeFactor) / 1000.0   // 1.3 – 3.5
        let normalized = (ease - 1.3) / (3.5 - 1.3)   // 0 – 1
        return max(1.0, min(10.0, 10.0 - normalized * 9.0))   // 10 (hard) → 1 (easy)
    }

    // MARK: - SQLite readers

    private struct AnkiModel {
        enum ModelType { case basic, cloze }
        let id: Int64
        let name: String
        let type: ModelType
        let fieldNames: [String]
    }

    private struct AnkiDeckInfo {
        let id: Int64
        let name: String
    }

    private struct AnkiNote {
        let id: Int64
        let modelID: Int64
        let tags: String
        let fields: String
    }

    private struct AnkiCardSchedule {
        let noteID: Int64
        let deckID: Int64
        let cardType: Int   // 0=new,1=learning,2=review,3=relearning
        let interval: Int   // days (positive) or seconds (negative)
        let easeFactor: Int // * 1000
        let reps: Int
        let lapses: Int
    }

    private func readCollectionMeta(db: OpaquePointer?) -> ([Int64: AnkiModel], [Int64: AnkiDeckInfo])? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT models, decks FROM col LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }

        let modelsJSON = columnString(stmt, 0)
        let decksJSON  = columnString(stmt, 1)

        let models = parseModels(modelsJSON)
        let decks  = parseDecks(decksJSON)
        return (models, decks)
    }

    private func parseModels(_ json: String) -> [Int64: AnkiModel] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        var result: [Int64: AnkiModel] = [:]
        for (key, value) in obj {
            guard let id = Int64(key), let dict = value as? [String: Any] else { continue }
            let name = dict["name"] as? String ?? "Untitled"
            let typeInt = dict["type"] as? Int ?? 0
            let modelType: AnkiModel.ModelType = typeInt == 1 ? .cloze : .basic
            let flds = (dict["flds"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            result[id] = AnkiModel(id: id, name: name, type: modelType, fieldNames: flds)
        }
        return result
    }

    private func parseDecks(_ json: String) -> [Int64: AnkiDeckInfo] {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }

        var result: [Int64: AnkiDeckInfo] = [:]
        for (key, value) in obj {
            guard let id = Int64(key), let dict = value as? [String: Any] else { continue }
            let name = dict["name"] as? String ?? "Imported"
            if id == 1 { continue }  // skip default deck
            result[id] = AnkiDeckInfo(id: id, name: name)
        }
        // Fallback: include default if no other decks
        if result.isEmpty {
            result[1] = AnkiDeckInfo(id: 1, name: "Imported from Anki")
        }
        return result
    }

    private func readNotes(db: OpaquePointer?) -> [AnkiNote] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id, mid, tags, flds FROM notes", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var notes: [AnkiNote] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id      = sqlite3_column_int64(stmt, 0)
            let mid     = sqlite3_column_int64(stmt, 1)
            let tags    = columnString(stmt, 2)
            let fields  = columnString(stmt, 3)
            notes.append(AnkiNote(id: id, modelID: mid, tags: tags, fields: fields))
        }
        return notes
    }

    private func readCardSchedules(db: OpaquePointer?) -> [Int64: AnkiCardSchedule] {
        var stmt: OpaquePointer?
        let sql = "SELECT nid, did, type, ivl, factor, reps, lapses FROM cards"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }

        var schedules: [Int64: AnkiCardSchedule] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let nid     = sqlite3_column_int64(stmt, 0)
            let did     = sqlite3_column_int64(stmt, 1)
            let type    = Int(sqlite3_column_int(stmt, 2))
            let ivl     = Int(sqlite3_column_int(stmt, 3))
            let factor  = Int(sqlite3_column_int(stmt, 4))
            let reps    = Int(sqlite3_column_int(stmt, 5))
            let lapses  = Int(sqlite3_column_int(stmt, 6))
            // Keep only the first card per note (ord=0) — simplification
            if schedules[nid] == nil {
                schedules[nid] = AnkiCardSchedule(
                    noteID: nid, deckID: did, cardType: type,
                    interval: ivl, easeFactor: factor, reps: reps, lapses: lapses
                )
            }
        }
        return schedules
    }

    // MARK: - Media

    private func parseMediaMap(tempDir: URL) -> [String: String] {
        let mediaFile = tempDir.appendingPathComponent("media")
        guard let data = try? Data(contentsOf: mediaFile),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return obj  // "0" → "image.jpg"
    }

    private func extractImage(from html: String, tempDir: URL, mediaMap: [String: String]) -> Data? {
        // Find first <img src="..."> in the field HTML
        let pattern = #"<img[^>]+src=["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let srcRange = Range(match.range(at: 1), in: html)
        else { return nil }

        let srcName = String(html[srcRange])

        // Find the numbered file in the media map
        let fileNumber = mediaMap.first(where: { $0.value == srcName })?.key ?? srcName
        let mediaPath = tempDir.appendingPathComponent(fileNumber)
        return try? Data(contentsOf: mediaPath)
    }

    // MARK: - HTML stripping

    private func stripHTML(_ html: String) -> String {
        // Remove <img ...> tags entirely (images handled separately)
        var text = html.replacingOccurrences(of: #"<img[^>]*>"#, with: "", options: .regularExpression)
        // Replace <br>, <br/>, <div>, <p> with newlines
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: #"</?(?:div|p)[^>]*>"#, with: "\n", options: .regularExpression)
        // Strip remaining tags
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        // Decode common HTML entities
        text = text
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&quot;", with: "\"")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - SQLite helper

    private func columnString(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, col) else { return "" }
        return String(cString: ptr)
    }
}

private extension String {
    var fileExists: Bool { FileManager.default.fileExists(atPath: self) }
}
