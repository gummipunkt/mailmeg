import Foundation

/// Finds the quoted earlier messages at the end of a plain-text body, so the app can
/// fold them away.
public enum QuotedText {
    /// Splits `text` into what was newly written and the quote that follows it.
    /// `quote` is nil when there is none, when the message is nothing but a quote, or
    /// when replies are written between or below the quoted lines.
    public static func split(_ text: String) -> (body: String, quote: String?) {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard let start = quoteStart(in: lines), start > 0 else { return (text, nil) }
        let body = lines[..<start].joined(separator: "\n").trimmingTrailingWhitespace()
        let quote = lines[start...].joined(separator: "\n").trimmingTrailingWhitespace()
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !quote.isEmpty else { return (text, nil) }
        return (body, quote)
    }

    private static func quoteStart(in lines: [String]) -> Int? {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }

        // Outlook style: a separator line, then the old message without ">" marks.
        if let index = trimmed.firstIndex(where: isOriginalMessageSeparator) {
            return index
        }

        // The block of ">" lines that runs to the end of the message.
        guard let last = trimmed.lastIndex(where: { !$0.isEmpty }), trimmed[last].hasPrefix(">") else { return nil }
        var start = last
        while start > 0, trimmed[start - 1].isEmpty || trimmed[start - 1].hasPrefix(">") {
            start -= 1
        }
        while start < last, trimmed[start].isEmpty { start += 1 }

        // "On … wrote:" above it belongs to the quote; it may be wrapped onto two lines.
        var above = start - 1
        while above >= 0, trimmed[above].isEmpty { above -= 1 }
        if above >= 0, isAttributionEnd(trimmed[above]) {
            if above > 0, !isAttributionStart(trimmed[above]), isAttributionStart(trimmed[above - 1]) {
                return above - 1
            }
            return above
        }
        return start
    }

    private static func isOriginalMessageSeparator(_ line: String) -> Bool {
        guard line.hasPrefix("-----"), line.hasSuffix("-----") else { return false }
        let lower = line.lowercased()
        return ["original message", "ursprüngliche nachricht", "originalnachricht", "original-nachricht", "message d'origine", "mensaje original"]
            .contains { lower.contains($0) }
    }

    private static let attributionVerbs = ["wrote", "schrieb", "geschrieben", "écrit", "escribió", "ha scritto"]

    private static func isAttributionEnd(_ line: String) -> Bool {
        guard line.hasSuffix(":") else { return false }
        let lower = line.lowercased()
        return attributionVerbs.contains { lower.contains($0) }
    }

    private static func isAttributionStart(_ line: String) -> Bool {
        let lower = line.lowercased()
        return ["on ", "am ", "le ", "el ", "il "].contains { lower.hasPrefix($0) }
    }
}

private extension String {
    func trimmingTrailingWhitespace() -> String {
        var result = Substring(self)
        while let last = result.last, last.isWhitespace || last.isNewline { result = result.dropLast() }
        return String(result)
    }
}
