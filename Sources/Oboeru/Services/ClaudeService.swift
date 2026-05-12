import Foundation
import PDFKit

// MARK: - Model

enum ClaudeModel: String, CaseIterable, Identifiable {
    // Update these identifiers as new Claude versions release
    case haiku  = "claude-haiku-4-5"
    case sonnet = "claude-sonnet-4-5"
    case opus   = "claude-opus-4-5"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .haiku:  return "Haiku 4.5"
        case .sonnet: return "Sonnet 4.5"
        case .opus:   return "Opus 4.5"
        }
    }

    var subtitle: String {
        switch self {
        case .haiku:  return "Fastest · Most affordable"
        case .sonnet: return "Best balance of speed & quality"
        case .opus:   return "Highest quality · Slower"
        }
    }
}

// MARK: - Generated card

struct AIGeneratedCard: Identifiable, Codable {
    var id       = UUID()
    var type:       String      // "basic" or "cloze"
    var front:      String
    var back:       String
    var tags:       [String]
    var difficulty: String      // "beginner" | "intermediate" | "advanced"
    var isIncluded: Bool = true

    enum CodingKeys: String, CodingKey { case type, front, back, tags, difficulty }

    init(from decoder: Decoder) throws {
        let c   = try decoder.container(keyedBy: CodingKeys.self)
        type       = try  c.decode(String.self,   forKey: .type)
        front      = try  c.decode(String.self,   forKey: .front)
        back       = (try? c.decode(String.self,   forKey: .back))       ?? ""
        tags       = (try? c.decode([String].self, forKey: .tags))       ?? []
        difficulty = (try? c.decode(String.self,   forKey: .difficulty)) ?? "beginner"
    }

    init(type: String, front: String, back: String, tags: [String], difficulty: String) {
        self.type = type; self.front = front; self.back = back
        self.tags = tags; self.difficulty = difficulty
    }
}

// MARK: - Errors

enum ClaudeImportError: LocalizedError {
    case noAPIKey
    case invalidURL
    case fetchFailed(Int)
    case unreadable(String)
    case unsupportedFormat(String)
    case apiError(String)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:                  return "No Claude API key set. Add one in Settings (⌘,)."
        case .invalidURL:               return "The URL is not valid."
        case .fetchFailed(let code):    return "Could not fetch the page (HTTP \(code))."
        case .unreadable(let msg):      return "Could not read content: \(msg)"
        case .unsupportedFormat(let e): return "Unsupported file format: .\(e)"
        case .apiError(let msg):        return "Claude API error: \(msg)"
        case .parseError(let msg):      return "Could not parse Claude's response: \(msg)"
        }
    }
}

// MARK: - Service

enum ClaudeService {

    // MARK: Text extraction

    static func extractText(from url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let doc = PDFDocument(url: url) else {
                throw ClaudeImportError.unreadable("Could not open PDF")
            }
            let text = (0..<doc.pageCount)
                .compactMap { doc.page(at: $0)?.string }
                .joined(separator: "\n\n")
            if text.isEmpty { throw ClaudeImportError.unreadable("PDF contained no extractable text") }
            return text
        case "txt", "md", "markdown":
            return try String(contentsOf: url, encoding: .utf8)
        default:
            if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
            throw ClaudeImportError.unsupportedFormat(url.pathExtension)
        }
    }

    // MARK: Web content

    static func fetchWebContent(from urlString: String) async throws -> (title: String, body: String) {
        guard let url = URL(string: urlString) else { throw ClaudeImportError.invalidURL }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClaudeImportError.fetchFailed(http.statusCode)
        }
        guard let html = String(data: data, encoding: .utf8) ??
                          String(data: data, encoding: .isoLatin1) else {
            throw ClaudeImportError.unreadable("Could not decode page encoding")
        }
        return parseHTML(html)
    }

    // MARK: Card generation

    static func generateCards(
        from text: String,
        topic: String   = "",
        cardCount: Int  = 20,
        model: ClaudeModel,
        apiKey: String
    ) async throws -> [AIGeneratedCard] {
        let truncated = String(text.prefix(32_000))    // safety cap (~8k tokens)
        let prompt    = buildPrompt(text: truncated, topic: topic, cardCount: cardCount)
        let raw       = try await callClaude(prompt: prompt, model: model, apiKey: apiKey)
        return try parseCards(from: raw)
    }

    // MARK: Key validation

    static func validateKey(_ apiKey: String) async throws {
        _ = try await callClaude(
            prompt: "Reply with the single word: OK",
            model: .haiku,
            apiKey: apiKey,
            maxTokens: 10
        )
    }

    // MARK: - Private

    private static func buildPrompt(text: String, topic: String, cardCount: Int) -> String {
        let hint = topic.isEmpty ? "" : " The subject is: \(topic)."
        return """
        You are an expert educator creating spaced-repetition flashcards.\(hint)

        Analyze the content below and generate exactly \(cardCount) high-quality flashcards.

        Rules:
        • Each card tests ONE atomic concept — no compound questions
        • Mix "basic" (Q&A) and "cloze" (fill-in-the-blank) cards
        • Cloze: wrap the answer in {{double braces}}, e.g. "Python lists are {{mutable}}"
        • Fronts are questions or prompts, never plain statements
        • difficulty: "beginner" = definitions/basics, "intermediate" = application, "advanced" = edge-cases/deep
        • tags: 1–3 lowercase topic tags per card
        • Avoid trivial, redundant, or overly obvious cards
        • Prefer testable knowledge over summaries

        Return ONLY a valid JSON array with no other text or markdown:
        [
          {"type":"basic","front":"<question>","back":"<answer>","tags":["tag"],"difficulty":"beginner"},
          {"type":"cloze","front":"<sentence with {{gap}}>","back":"","tags":["tag"],"difficulty":"intermediate"}
        ]

        Content:
        ---
        \(text)
        ---
        """
    }

    private static func callClaude(
        prompt: String,
        model: ClaudeModel,
        apiKey: String,
        maxTokens: Int = 8000
    ) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey,        forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01",  forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model":      model.rawValue,
            "max_tokens": maxTokens,
            "messages":   [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClaudeImportError.apiError("HTTP \(http.statusCode): \(body.prefix(300))")
        }

        struct Envelope: Decodable {
            struct Content: Decodable { let text: String }
            let content: [Content]
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        return envelope.content.first?.text ?? ""
    }

    private static func parseCards(from raw: String) throws -> [AIGeneratedCard] {
        var json = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip markdown code fences Claude sometimes wraps around JSON
        if json.hasPrefix("```") {
            let lines = json.components(separatedBy: "\n")
            json = lines.dropFirst().joined(separator: "\n")
            if json.hasSuffix("```") { json = String(json.dropLast(3)) }
            json = json.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = json.data(using: .utf8) else {
            throw ClaudeImportError.parseError("Response could not be encoded")
        }
        do {
            return try JSONDecoder().decode([AIGeneratedCard].self, from: data)
        } catch {
            throw ClaudeImportError.parseError(error.localizedDescription)
        }
    }

    // MARK: HTML → plain text

    private static func parseHTML(_ html: String) -> (title: String, body: String) {
        let title = extractHTMLTitle(from: html)
        var text  = html

        // Remove noisy tags wholesale
        for tag in ["script", "style", "nav", "header", "footer", "iframe", "noscript", "aside"] {
            text = stripTag(tag, from: text)
        }
        // Strip remaining HTML tags
        text = applyRegex("<[^>]+>", to: text, replacement: " ")

        // Decode common HTML entities
        text = text
            .replacingOccurrences(of: "&amp;",   with: "&")
            .replacingOccurrences(of: "&lt;",    with: "<")
            .replacingOccurrences(of: "&gt;",    with: ">")
            .replacingOccurrences(of: "&nbsp;",  with: " ")
            .replacingOccurrences(of: "&quot;",  with: "\"")
            .replacingOccurrences(of: "&#39;",   with: "'")
            .replacingOccurrences(of: "&apos;",  with: "'")

        // Collapse whitespace
        text = applyRegex("[ \\t]+",  to: text, replacement: " ")
        text = applyRegex("\\n{3,}",  to: text, replacement: "\n\n")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return (title, text)
    }

    private static func extractHTMLTitle(from html: String) -> String {
        guard let s = html.range(of: "<title", options: .caseInsensitive),
              let te = html[s.upperBound...].range(of: ">"),
              let e  = html[te.upperBound...].range(of: "</title>", options: .caseInsensitive) else {
            return ""
        }
        return String(html[te.upperBound..<e.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripTag(_ tag: String, from html: String) -> String {
        applyRegex("<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                   to: html,
                   replacement: " ",
                   options: [.caseInsensitive])
    }

    private static func applyRegex(
        _ pattern: String,
        to text: String,
        replacement: String,
        options: NSRegularExpression.Options = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: replacement
        )
    }
}
