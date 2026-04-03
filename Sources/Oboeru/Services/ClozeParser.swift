import Foundation

// ClozeParser is a pure static utility — no state, no dependencies.
//
// Syntax: {{text}} or {{text::hint}}
//   - text:  the answer being tested
//   - hint:  optional hint shown in the blank (defaults to "...")
//
// Example:  "The {{capital::city}} of France is {{Paris}}."
//   ordinal 1 → blank = "[city]",  full = "capital"
//   ordinal 2 → blank = "[...]",   full = "Paris"
//
// Each ordinal becomes a sibling OboerCard that schedules independently.

enum ClozeParser {

    // MARK: - Types

    enum Token {
        case plain(String)
        case gap(ordinal: Int, answer: String, hint: String?)
    }

    struct Sibling {
        let ordinal: Int
        let maskedText: String      // gap for this ordinal shown as blank, others revealed
        let fullText: String        // all gaps revealed (shown on back of card)
    }

    // MARK: - Regex

    private static let pattern = try! NSRegularExpression(
        pattern: #"\{\{([^}:]+?)(?:::([^}]*))?\}\}"#,
        options: []
    )

    // MARK: - Public API

    /// Tokenizes cloze source text into plain strings and gap tokens.
    static func parse(_ raw: String) -> [Token] {
        var tokens: [Token] = []
        var cursor = raw.startIndex
        var ordinal = 1

        let matches = pattern.matches(
            in: raw,
            range: NSRange(raw.startIndex..., in: raw)
        )

        for match in matches {
            let matchRange = Range(match.range, in: raw)!

            // Plain text before this gap
            if cursor < matchRange.lowerBound {
                tokens.append(.plain(String(raw[cursor..<matchRange.lowerBound])))
            }

            let answer = String(raw[Range(match.range(at: 1), in: raw)!])
            let hint: String?
            if match.range(at: 2).location != NSNotFound,
               let hintRange = Range(match.range(at: 2), in: raw) {
                hint = String(raw[hintRange])
            } else {
                hint = nil
            }

            tokens.append(.gap(ordinal: ordinal, answer: answer, hint: hint))
            ordinal += 1
            cursor = matchRange.upperBound
        }

        // Trailing plain text
        if cursor < raw.endIndex {
            tokens.append(.plain(String(raw[cursor...])))
        }

        return tokens
    }

    /// Returns the number of distinct cloze gaps in the text.
    static func gapCount(_ raw: String) -> Int {
        pattern.numberOfMatches(in: raw, range: NSRange(raw.startIndex..., in: raw))
    }

    /// Returns true if there is at least one gap marker.
    static func isValid(_ raw: String) -> Bool {
        gapCount(raw) > 0
    }

    /// Generates one Sibling per gap ordinal.
    /// Each sibling masks its own gap and reveals all others.
    static func siblings(for raw: String) -> [Sibling] {
        let tokens = parse(raw)
        let totalGaps = tokens.compactMap { if case .gap(let ord, _, _) = $0 { return ord } else { return nil } }.max() ?? 0

        return (1...max(1, totalGaps)).compactMap { targetOrdinal -> Sibling? in
            guard tokens.contains(where: { if case .gap(let ord, _, _) = $0 { return ord == targetOrdinal } else { return false } }) else {
                return nil
            }
            return Sibling(
                ordinal: targetOrdinal,
                maskedText: renderMasked(tokens: tokens, masking: targetOrdinal),
                fullText: renderFull(tokens: tokens)
            )
        }
    }

    /// Renders text with the given ordinal masked and all others revealed.
    /// Convenience overload that parses first — used in OboerCard.displayFront.
    static func renderMasked(_ raw: String, ordinal: Int) -> String {
        renderMasked(tokens: parse(raw), masking: ordinal)
    }

    /// Renders text with all gaps filled in (used for card backs).
    static func renderFull(_ raw: String) -> String {
        renderFull(tokens: parse(raw))
    }

    // MARK: - Private rendering

    private static func renderMasked(tokens: [Token], masking targetOrdinal: Int) -> String {
        tokens.map { token in
            switch token {
            case .plain(let text):
                return text
            case .gap(let ordinal, let answer, let hint):
                if ordinal == targetOrdinal {
                    let display = hint.map { "[\($0)]" } ?? "[...]"
                    return display
                } else {
                    return answer
                }
            }
        }.joined()
    }

    private static func renderFull(tokens: [Token]) -> String {
        tokens.map { token in
            switch token {
            case .plain(let text): return text
            case .gap(_, let answer, _): return answer
            }
        }.joined()
    }
}
