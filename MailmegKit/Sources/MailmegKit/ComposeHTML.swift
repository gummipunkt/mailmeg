import Foundation

/// Builds the HTML alternative of an outgoing plain-text message: links are clickable,
/// quoted lines become a blockquote, and the plain-text signature is replaced by the
/// original HTML signature from Gmail (so logos, links and formatting survive).
public enum ComposeHTML {
    public static func render(text: String, signatureText: String? = nil, signatureHTML: String? = nil) -> String {
        var before = text
        var after = ""
        var signature: String?
        if let signatureText, !signatureText.isEmpty, let signatureHTML, !signatureHTML.isEmpty,
           let range = text.range(of: signatureText) {
            before = String(text[..<range.lowerBound])
            after = String(text[range.upperBound...])
            signature = signatureHTML
        }

        var html = renderPlain(before)
        if let signature {
            html += "<div class=\"gmail_signature\">\(signature)</div>"
            html += renderPlain(after)
        }
        return "<div dir=\"auto\" style=\"font-family: -apple-system, Helvetica, Arial, sans-serif;\">\(html)</div>"
    }

    /// Plain text → HTML, grouping lines that start with ">" into blockquotes.
    static func renderPlain(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        var output = ""
        var quoteLines: [String] = []

        func flushQuote() {
            guard !quoteLines.isEmpty else { return }
            let inner = quoteLines.map { line -> String in
                var stripped = Substring(line)
                if stripped.hasPrefix(">") { stripped = stripped.dropFirst() }
                if stripped.hasPrefix(" ") { stripped = stripped.dropFirst() }
                return String(stripped)
            }.joined(separator: "\n")
            output += "<blockquote style=\"margin:0 0 0 .8ex;border-left:1px solid #ccc;padding-left:1ex\">"
                + renderPlain(inner) + "</blockquote>"
            quoteLines = []
        }

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var plainLines: [String] = []
        func flushPlain() {
            guard !plainLines.isEmpty else { return }
            output += plainLines.map { HTMLText.html(fromPlainText: $0) }.joined(separator: "<br>")
            plainLines = []
        }

        for line in lines {
            if line.hasPrefix(">") {
                if !plainLines.isEmpty { flushPlain(); output += "<br>" }
                quoteLines.append(line)
            } else {
                flushQuote()
                plainLines.append(line)
            }
        }
        flushQuote()
        flushPlain()
        return output
    }
}
