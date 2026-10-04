import Foundation

public struct AttachmentInfo: Identifiable, Hashable, Sendable, Codable {
    public var id: String { "\(messageID)/\(partID)" }
    public let messageID: String
    public let partID: String
    public let filename: String
    public let mimeType: String
    public let size: Int
    public let attachmentID: String?
    public let inlineData: Data?
    public let contentID: String?
    public let isInline: Bool

    public init(messageID: String, partID: String, filename: String, mimeType: String, size: Int, attachmentID: String?, inlineData: Data?, contentID: String?, isInline: Bool) {
        self.messageID = messageID
        self.partID = partID
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.attachmentID = attachmentID
        self.inlineData = inlineData
        self.contentID = contentID
        self.isInline = isInline
    }
}

/// The displayable content of a Gmail message, extracted from its MIME tree.
public struct MessageContent: Sendable {
    public var html: String?
    public var plainText: String?
    /// All parts with a filename or a Content-ID (attachments and inline images).
    public var parts: [AttachmentInfo]
    /// The calendar invitation (`text/calendar` or an `.ics` file), if the message carries one.
    public var calendar: AttachmentInfo?

    /// Attachments the user should see as files (excludes inline images referenced by the HTML).
    public var visibleAttachments: [AttachmentInfo] {
        parts.filter { part in
            guard part.isInline, let contentID = part.contentID, let html else {
                return !part.filename.isEmpty
            }
            return !html.contains("cid:\(contentID)")
        }
    }

    public init(message: GmailMessage) {
        html = nil
        plainText = nil
        parts = []
        calendar = nil
        if let payload = message.payload {
            visit(payload, messageID: message.id)
        }
    }

    private mutating func visit(_ part: MessagePart, messageID: String) {
        let mimeType = (part.mimeType ?? "").lowercased()
        if let children = part.parts, !children.isEmpty {
            // For multipart/alternative both the HTML and the plain-text variant are kept;
            // the UI prefers HTML and uses plain text for quoting.
            for child in children { visit(child, messageID: messageID) }
            return
        }

        let disposition = part.header("Content-Disposition").map(HeaderValue.init)
        let contentType = part.header("Content-Type").map(HeaderValue.init)
        let filename = part.filename ?? ""
        let contentID = part.header("Content-ID").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "<> ")) }
        let isAttachment = !filename.isEmpty || disposition?.value == "attachment"

        let isCalendar = mimeType == "text/calendar" || mimeType == "application/ics"
            || filename.lowercased().hasSuffix(".ics")
        if isCalendar, calendar == nil || (calendar?.inlineData == nil && part.body?.attachmentId == nil) {
            calendar = AttachmentInfo(
                messageID: messageID,
                partID: part.partId ?? UUID().uuidString,
                filename: filename.isEmpty ? "invite.ics" : filename,
                mimeType: mimeType,
                size: part.body?.size ?? 0,
                attachmentID: part.body?.attachmentId,
                inlineData: part.body?.attachmentId == nil ? part.body?.decodedData : nil,
                contentID: nil,
                isInline: false
            )
        }
        if isCalendar && !isAttachment { return }

        if !isAttachment, mimeType == "text/html" || mimeType == "text/plain" {
            let text = part.body?.decodedData.map { TextDecoding.body(from: $0, charset: contentType?["charset"]) } ?? ""
            if mimeType == "text/html" {
                html = html.map { $0 + "\n" + text } ?? text
            } else {
                plainText = plainText.map { $0 + "\n" + text } ?? text
            }
            return
        }

        guard isAttachment || contentID != nil else { return }
        parts.append(AttachmentInfo(
            messageID: messageID,
            partID: part.partId ?? UUID().uuidString,
            filename: filename,
            mimeType: mimeType.isEmpty ? "application/octet-stream" : mimeType,
            size: part.body?.size ?? 0,
            attachmentID: part.body?.attachmentId,
            inlineData: part.body?.attachmentId == nil ? part.body?.decodedData : nil,
            contentID: contentID,
            isInline: disposition?.value == "inline" || (disposition == nil && contentID != nil)
        ))
    }

    /// Plain text for quoting in replies, derived from HTML if necessary.
    public var quotableText: String {
        if let plainText, !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plainText
        }
        return html.map(HTMLText.plainText(fromHTML:)) ?? ""
    }
}

public enum HTMLText {
    private static let entities: [String: String] = [
        "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'",
    ]

    public static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = string
        for (entity, replacement) in entities where entity != "&amp;" {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        // Numeric entities: &#123; and &#x1F600;
        if let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") {
            let ns = result as NSString
            var output = ""
            var location = 0
            for match in regex.matches(in: result, range: NSRange(location: 0, length: ns.length)) {
                output += ns.substring(with: NSRange(location: location, length: match.range.location - location))
                let isHex = match.range(at: 1).length > 0
                let digits = ns.substring(with: match.range(at: 2))
                if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
                    output.unicodeScalars.append(scalar)
                } else {
                    output += ns.substring(with: match.range)
                }
                location = match.range.location + match.range.length
            }
            output += ns.substring(from: location)
            result = output
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    public static func escape(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// Very small HTML → text conversion, good enough for quoting.
    public static func plainText(fromHTML html: String) -> String {
        var text = html
        let replacements: [(String, String)] = [
            ("(?is)<(script|style|head)[^>]*>.*?</\\1>", ""),
            ("(?i)<br\\s*/?>", "\n"),
            ("(?i)</(p|div|tr|li|h[1-6]|blockquote)>", "\n"),
            ("(?s)<[^>]+>", ""),
            ("[ \\t]+\\n", "\n"),
            ("\\n{3,}", "\n\n"),
        ]
        for (pattern, template) in replacements {
            text = text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return decodeEntities(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Converts plain text into HTML, turning URLs and email addresses into links.
    public static func html(fromPlainText text: String) -> String {
        let ns = text as NSString
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        var output = ""
        var location = 0
        for match in detector?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? [] {
            guard let url = match.url else { continue }
            output += escape(ns.substring(with: NSRange(location: location, length: match.range.location - location)))
            output += "<a href=\"\(escape(url.absoluteString))\">\(escape(ns.substring(with: match.range)))</a>"
            location = match.range.location + match.range.length
        }
        output += escape(ns.substring(from: location))
        return output
    }
}
