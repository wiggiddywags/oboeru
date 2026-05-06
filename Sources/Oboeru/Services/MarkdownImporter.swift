import Foundation

// MarkdownImporter parses a Markdown `.md` file and returns a flat array of
// MarkdownImportCard values ready for preview / insertion into a deck.
//
// Supported formats (auto-detected):
//
//  1. QA format      — lines starting with "Q:" / "A:" (or "**Q:**" / "**A:**")
//  2. Header format  — "## Front\n\nBack text\n\n---"  or "# Front\n\nBack"
//  3. Separator format — cards delimited by "---", first paragraph = front, rest = back
//  4. Pipe format    — "front | back" (one card per line)

// MARK: - Public types

struct MarkdownImportCard {
    let frontText: String
    let backText: String
    let tags: [String]          // words starting with # found anywhere in the card
}

enum MarkdownFormat {
    case qa          // Q: / A: pairs
    case header      // ## heading + body block
    case separator   // front\n\nback\n\n---
    case pipe        // front | back
}

// MARK: - Importer

enum MarkdownImporter {

    // MARK: - Public API

    /// Reads the file at `url` and returns an array of cards.
    static func `import`(from url: URL) throws -> [MarkdownImportCard] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let format  = detectFormat(content)
        return parse(content: content, format: format)
    }

    /// Detects the predominant card format by inspecting the first 20 non-empty lines.
    static func detectFormat(_ content: String) -> MarkdownFormat {
        let lines = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(20)

        var qaScore         = 0
        var headerScore     = 0
        var separatorScore  = 0
        var pipeScore       = 0

        for line in lines {
            // QA
            if line.hasPrefix("Q:") || line.hasPrefix("A:") ||
               line.hasPrefix("**Q:**") || line.hasPrefix("**A:**") {
                qaScore += 2
            }
            // Header
            if line.hasPrefix("## ") || line.hasPrefix("# ") {
                headerScore += 2
            }
            // Separator
            if line == "---" || line == "***" || line == "___" {
                separatorScore += 2
            }
            // Pipe
            if line.contains(" | ") && !line.hasPrefix("#") {
                pipeScore += 2
            }
        }

        let max = Swift.max(qaScore, headerScore, separatorScore, pipeScore)
        if max == 0 {
            // Fallback heuristic: if there's a | in any line, pipe; else separator
            let hasPipe = lines.contains { $0.contains("|") && !$0.hasPrefix("#") }
            return hasPipe ? .pipe : .separator
        }
        if qaScore         == max { return .qa }
        if pipeScore       == max { return .pipe }
        if headerScore     == max { return .header }
        return .separator
    }

    // MARK: - Dispatch

    private static func parse(content: String, format: MarkdownFormat) -> [MarkdownImportCard] {
        switch format {
        case .qa:        return parseQA(content)
        case .header:    return parseHeader(content)
        case .separator: return parseSeparator(content)
        case .pipe:      return parsePipe(content)
        }
    }

    // MARK: - QA parser

    // Supports:
    //   Q: What is X?
    //   A: It is Y.
    //
    //   **Q:** What is X?
    //   **A:** It is Y.
    //
    // Multi-line answers: lines between one A: and the next Q: are all part of the answer.

    private static func parseQA(_ content: String) -> [MarkdownImportCard] {
        let lines = content.components(separatedBy: .newlines)
        var cards: [MarkdownImportCard] = []

        var currentFront: String? = nil
        var backLines:    [String] = []

        let stripQAPrefix: (String) -> String? = { line in
            let prefixes = ["**Q:**", "**A:**", "Q:", "A:"]
            for prefix in prefixes {
                if line.hasPrefix(prefix) {
                    return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                }
            }
            return nil
        }

        let isQLine: (String) -> Bool = { line in
            line.hasPrefix("Q:") || line.hasPrefix("**Q:**")
        }

        let isALine: (String) -> Bool = { line in
            line.hasPrefix("A:") || line.hasPrefix("**A:**")
        }

        func flush() {
            guard let front = currentFront, !front.isEmpty else { return }
            let back = backLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let card = makeCard(front: front, back: back)
            if card.frontText.isEmpty { return }
            cards.append(card)
        }

        var collectingAnswer = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if isQLine(trimmed) {
                flush()
                currentFront   = stripQAPrefix(trimmed) ?? ""
                backLines      = []
                collectingAnswer = false
            } else if isALine(trimmed) {
                let firstLine = stripQAPrefix(trimmed) ?? ""
                backLines = firstLine.isEmpty ? [] : [firstLine]
                collectingAnswer = true
            } else if collectingAnswer {
                backLines.append(trimmed)
            }
        }
        flush()
        return cards
    }

    // MARK: - Header parser

    // Format:
    //   ## Front text
    //
    //   Back text (may span multiple paragraphs)
    //
    //   ---   ← optional card divider (reset)
    //
    //   ## Next card front
    //   …

    private static func parseHeader(_ content: String) -> [MarkdownImportCard] {
        let lines = content.components(separatedBy: .newlines)
        var cards: [MarkdownImportCard] = []

        var currentFront: String? = nil
        var bodyLines:    [String] = []

        func flush() {
            guard let front = currentFront, !front.isEmpty else { return }
            let back = bodyLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let card = makeCard(front: front, back: back)
            if !card.frontText.isEmpty { cards.append(card) }
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") || trimmed.hasPrefix("# ") {
                flush()
                let rawFront = trimmed
                    .replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
                currentFront = rawFront
                bodyLines    = []
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                // Explicit card separator: flush and reset
                flush()
                currentFront = nil
                bodyLines    = []
            } else {
                bodyLines.append(trimmed)
            }
        }
        flush()
        return cards
    }

    // MARK: - Separator parser

    // Cards are separated by "---". Within each block, the first non-empty paragraph
    // is the front; everything after the first blank line is the back.

    private static func parseSeparator(_ content: String) -> [MarkdownImportCard] {
        // Split on horizontal rules (--- / *** / ___)
        let separatorRegex = try? NSRegularExpression(pattern: #"^(?:---|\*\*\*|___)$"#,
                                                      options: .init(rawValue: NSString.CompareOptions.regularExpression.rawValue))
        let blocks: [String]

        if let re = separatorRegex {
            let nsContent = content as NSString
            let ranges = re.matches(in: content, range: NSRange(content.startIndex..., in: content))
            var parts: [String] = []
            var lastEnd = content.startIndex

            for match in ranges {
                guard let matchRange = Range(match.range, in: content) else { continue }
                let chunk = String(content[lastEnd..<matchRange.lowerBound])
                parts.append(chunk)
                lastEnd = matchRange.upperBound
            }
            parts.append(String(content[lastEnd...]))
            blocks = parts
            _ = nsContent  // satisfy compiler
        } else {
            blocks = [content]
        }

        return blocks.compactMap { block -> MarkdownImportCard? in
            let trimmedBlock = block.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedBlock.isEmpty else { return nil }

            // Split on blank lines to get paragraphs
            let paragraphs = splitIntoParagraphs(trimmedBlock)
            guard let firstParagraph = paragraphs.first, !firstParagraph.isEmpty else { return nil }

            let front = firstParagraph
            let back  = paragraphs.dropFirst().joined(separator: "\n\n")
            let card  = makeCard(front: front, back: back)
            return card.frontText.isEmpty ? nil : card
        }
    }

    // MARK: - Pipe parser

    // Each non-blank line containing " | " is one card.
    // Text before the first " | " = front; text after = back.
    // Lines without " | " are skipped.

    private static func parsePipe(_ content: String) -> [MarkdownImportCard] {
        return content
            .components(separatedBy: .newlines)
            .compactMap { line -> MarkdownImportCard? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.contains(" | "), !trimmed.hasPrefix("#") else { return nil }
                guard let separatorRange = trimmed.range(of: " | ") else { return nil }

                let front = String(trimmed[trimmed.startIndex..<separatorRange.lowerBound])
                let back  = String(trimmed[separatorRange.upperBound...])
                let card  = makeCard(front: front, back: back)
                return card.frontText.isEmpty ? nil : card
            }
    }

    // MARK: - Shared card factory

    /// Strips markdown formatting, extracts `#tag` words, and returns a MarkdownImportCard.
    private static func makeCard(front: String, back: String) -> MarkdownImportCard {
        var (cleanFront, frontTags) = extractTagsAndClean(front)
        var (cleanBack,  backTags)  = extractTagsAndClean(back)

        cleanFront = stripMarkdown(cleanFront)
        cleanBack  = stripMarkdown(cleanBack)

        let allTags = Array(Set(frontTags + backTags)).sorted()
        return MarkdownImportCard(
            frontText: cleanFront.trimmingCharacters(in: .whitespacesAndNewlines),
            backText:  cleanBack.trimmingCharacters(in: .whitespacesAndNewlines),
            tags:      allTags
        )
    }

    // MARK: - Markdown stripping

    /// Removes common markdown formatting characters from text.
    static func stripMarkdown(_ text: String) -> String {
        var s = text

        // Bold/italic: ***text***, **text**, *text*, __text__, _text_
        s = s.replacingOccurrences(of: #"\*{3}([^*]+)\*{3}"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*{2}([^*]+)\*{2}"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*([^*\n]+)\*"#,     with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"_{2}([^_]+)_{2}"#,   with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"_([^_\n]+)_"#,       with: "$1", options: .regularExpression)

        // Inline code: `code`
        s = s.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)

        // Blockquote, list, and heading markers at line start — process line by line
        s = s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var l = String(line)
                l = l.replacingOccurrences(of: #"^>\s?"#, with: "", options: .regularExpression)
                l = l.replacingOccurrences(of: #"^[-*+]\s+"#, with: "", options: .regularExpression)
                l = l.replacingOccurrences(of: #"^#{1,6}\s+"#, with: "", options: .regularExpression)
                return l
            }
            .joined(separator: "\n")

        return s
    }

    // MARK: - Tag extraction

    /// Finds all `#word` tokens in text, removes them, and returns (cleanedText, tags).
    private static func extractTagsAndClean(_ text: String) -> (String, [String]) {
        guard let re = try? NSRegularExpression(pattern: #"(?<!\w)#([A-Za-z][A-Za-z0-9_]*)"#) else {
            return (text, [])
        }

        var tags: [String] = []
        let ns      = text as NSString
        let range   = NSRange(location: 0, length: ns.length)
        let matches = re.matches(in: text, range: range)

        for match in matches {
            if let tagRange = Range(match.range(at: 1), in: text) {
                tags.append(String(text[tagRange]))
            }
        }

        // Remove the #tag tokens from the text
        let cleaned = re.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        return (cleaned, tags)
    }

    // MARK: - Paragraph splitting

    /// Splits a block of text on blank lines (two or more newlines).
    private static func splitIntoParagraphs(_ text: String) -> [String] {
        // Split on one or more blank lines
        let paragraphRegex = try? NSRegularExpression(pattern: #"\n{2,}"#)
        guard let re = paragraphRegex else {
            return [text]
        }
        let nsText   = text as NSString
        let range    = NSRange(location: 0, length: nsText.length)
        let ranges   = re.matches(in: text, range: range)

        var parts: [String] = []
        var lastEnd = text.startIndex

        for match in ranges {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let chunk = String(text[lastEnd..<matchRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty { parts.append(chunk) }
            lastEnd = matchRange.upperBound
        }
        let tail = String(text[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { parts.append(tail) }
        return parts
    }
}
