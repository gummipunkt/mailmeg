import Foundation

/// One stretch of identically formatted text from the compose editor.
/// The editor stores the body as runs, so formatting survives in the draft and can be
/// rendered as HTML when the message is sent.
public struct RichTextRun: Codable, Hashable, Sendable {
    public var text: String
    public var isBold = false
    public var isItalic = false
    public var isUnderlined = false
    public var isStruck = false
    public var link: String?
    /// `#rrggbb`, or nil for the default text colour.
    public var colorHex: String?
    /// Point size, or nil for the default size.
    public var fontSize: Double?

    public init(text: String, isBold: Bool = false, isItalic: Bool = false, isUnderlined: Bool = false, isStruck: Bool = false,
                link: String? = nil, colorHex: String? = nil, fontSize: Double? = nil) {
        self.text = text
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.isStruck = isStruck
        self.link = link
        self.colorHex = colorHex
        self.fontSize = fontSize
    }

    /// True if the run carries any formatting at all.
    public var isFormatted: Bool {
        isBold || isItalic || isUnderlined || isStruck || link != nil || colorHex != nil || fontSize != nil
    }

    public func with(text: String) -> RichTextRun {
        var copy = self
        copy.text = text
        return copy
    }
}

/// Renders the formatted body of an outgoing message as HTML.
///
/// Paragraphs become `<div>`s, lines starting with "• " or "1. " become lists, quoted
/// lines (">") a blockquote, and the plain-text signature is swapped for Gmail's HTML
/// signature — like `ComposeHTML`, but keeping bold, italic, links, colours and sizes.
public enum RichTextHTML {
    public static let bulletPrefix = "• "

    public static func render(runs: [RichTextRun], signatureText: String? = nil, signatureHTML: String? = nil) -> String {
        let text = runs.map(\.text).joined()
        var html: String
        if let signatureText, !signatureText.isEmpty, let signatureHTML, !signatureHTML.isEmpty,
           let range = text.range(of: signatureText) {
            let start = text.utf16.distance(from: text.startIndex, to: range.lowerBound)
            let end = text.utf16.distance(from: text.startIndex, to: range.upperBound)
            let (before, rest) = split(runs, atUTF16: start)
            let (_, after) = split(rest, atUTF16: end - start)
            html = renderBlocks(before) + "<div class=\"gmail_signature\">\(signatureHTML)</div>" + renderBlocks(after)
        } else {
            html = renderBlocks(runs)
        }
        return "<div dir=\"auto\" style=\"font-family: -apple-system, Helvetica, Arial, sans-serif;\">\(html)</div>"
    }

    // MARK: - Blocks

    private enum LineKind: Equatable {
        case text, quote, bullet, numbered
    }

    static func renderBlocks(_ runs: [RichTextRun]) -> String {
        guard runs.contains(where: { !$0.text.isEmpty }) else { return "" }
        var lines = splitLines(runs)
        // A trailing newline ends the last paragraph; it does not start an empty one.
        if lines.count > 1, lines.last?.isEmpty == true { lines.removeLast() }
        var output = ""
        var index = 0
        while index < lines.count {
            let kind = kind(of: lines[index])
            var group: [[RichTextRun]] = []
            while index < lines.count, self.kind(of: lines[index]) == kind, kind != .text || group.isEmpty {
                group.append(lines[index])
                index += 1
            }
            switch kind {
            case .text:
                let inner = inline(group[0])
                output += "<div>\(inner.isEmpty ? "<br>" : inner)</div>"
            case .quote:
                let plain = group.map { $0.map(\.text).joined() }.joined(separator: "\n")
                output += "<div>\(ComposeHTML.renderPlain(plain))</div>"
            case .bullet, .numbered:
                let tag = kind == .bullet ? "ul" : "ol"
                let items = group.map { line -> String in
                    let prefixLength = listPrefixLength(line.map(\.text).joined())
                    return "<li>\(inline(split(line, atUTF16: prefixLength).1))</li>"
                }
                output += "<\(tag) style=\"margin:0 0 0 1.4em;padding:0\">\(items.joined())</\(tag)>"
            }
        }
        return output
    }

    private static func kind(of line: [RichTextRun]) -> LineKind {
        let text = line.map(\.text).joined()
        if text.hasPrefix(">") { return .quote }
        if text.hasPrefix(bulletPrefix) { return .bullet }
        if numberedPrefixLength(text) != nil { return .numbered }
        return .text
    }

    /// Length (UTF-16) of a "12. " prefix, if the line starts with one.
    public static func numberedPrefixLength(_ text: String) -> Int? {
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let rest = text.dropFirst(digits.count)
        guard rest.hasPrefix(". ") else { return nil }
        return digits.count + 2
    }

    private static func listPrefixLength(_ text: String) -> Int {
        if text.hasPrefix(bulletPrefix) { return bulletPrefix.utf16.count }
        return numberedPrefixLength(text) ?? 0
    }

    // MARK: - Inline

    static func inline(_ runs: [RichTextRun]) -> String {
        runs.map { run -> String in
            guard !run.text.isEmpty else { return "" }
            var html: String
            if let link = run.link {
                html = "<a href=\"\(HTMLText.escape(link))\">\(HTMLText.escape(run.text))</a>"
            } else {
                html = HTMLText.html(fromPlainText: run.text)
            }
            // Keep runs of spaces visible.
            html = html.replacingOccurrences(of: "  ", with: " &nbsp;")
            if run.isBold { html = "<b>\(html)</b>" }
            if run.isItalic { html = "<i>\(html)</i>" }
            if run.isUnderlined { html = "<u>\(html)</u>" }
            if run.isStruck { html = "<s>\(html)</s>" }
            var styles: [String] = []
            if let color = run.colorHex { styles.append("color:\(HTMLText.escape(color))") }
            if let size = run.fontSize { styles.append("font-size:\(Int(size.rounded()))px") }
            if !styles.isEmpty { html = "<span style=\"\(styles.joined(separator: ";"))\">\(html)</span>" }
            return html
        }.joined()
    }

    // MARK: - Splitting

    /// Splits runs into lines at "\n" (the newline itself is dropped).
    static func splitLines(_ runs: [RichTextRun]) -> [[RichTextRun]] {
        var lines: [[RichTextRun]] = [[]]
        for run in runs {
            let parts = run.text.components(separatedBy: "\n")
            for (offset, part) in parts.enumerated() {
                if offset > 0 { lines.append([]) }
                if !part.isEmpty { lines[lines.count - 1].append(run.with(text: part)) }
            }
        }
        return lines
    }

    /// Splits runs at a UTF-16 offset into the joined text.
    static func split(_ runs: [RichTextRun], atUTF16 offset: Int) -> ([RichTextRun], [RichTextRun]) {
        var before: [RichTextRun] = []
        var after: [RichTextRun] = []
        var position = 0
        for run in runs {
            let length = run.text.utf16.count
            if position + length <= offset {
                before.append(run)
            } else if position >= offset {
                after.append(run)
            } else {
                let cut = offset - position
                let utf16 = run.text.utf16
                let index = utf16.index(utf16.startIndex, offsetBy: cut)
                // Never cut inside a surrogate pair or grapheme.
                if let split = index.samePosition(in: run.text) {
                    before.append(run.with(text: String(run.text[..<split])))
                    after.append(run.with(text: String(run.text[split...])))
                } else {
                    before.append(run)
                }
            }
            position += length
        }
        return (before, after)
    }
}
