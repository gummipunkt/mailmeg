import Foundation

public struct OutgoingAttachment: Hashable, Sendable {
    public var filename: String
    public var mimeType: String
    public var data: Data

    public init(filename: String, mimeType: String, data: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}

public struct OutgoingMessage: Sendable {
    public var from: EmailAddress?
    public var replyTo: [EmailAddress]
    public var to: [EmailAddress]
    public var cc: [EmailAddress]
    public var bcc: [EmailAddress]
    public var subject: String
    public var textBody: String
    public var htmlBody: String?
    public var inReplyTo: String?
    public var references: [String]
    public var attachments: [OutgoingAttachment]

    public init(
        from: EmailAddress? = nil,
        replyTo: [EmailAddress] = [],
        to: [EmailAddress],
        cc: [EmailAddress] = [],
        bcc: [EmailAddress] = [],
        subject: String,
        textBody: String,
        htmlBody: String? = nil,
        inReplyTo: String? = nil,
        references: [String] = [],
        attachments: [OutgoingAttachment] = []
    ) {
        self.from = from
        self.replyTo = replyTo
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.textBody = textBody
        self.htmlBody = htmlBody
        self.inReplyTo = inReplyTo
        self.references = references
        self.attachments = attachments
    }
}

/// Serialises an `OutgoingMessage` into an RFC 5322 / MIME message.
public struct MIMEBuilder {
    var makeBoundary: () -> String
    var now: () -> Date

    public init(makeBoundary: @escaping () -> String = { "mailmeg-\(UUID().uuidString)" }, now: @escaping () -> Date = Date.init) {
        self.makeBoundary = makeBoundary
        self.now = now
    }

    public func build(_ message: OutgoingMessage) -> Data {
        var headers: [String] = []
        if let from = message.from { headers.append("From: \(Self.encodeAddress(from))") }
        if !message.replyTo.isEmpty { headers.append("Reply-To: \(Self.encodeAddressList(message.replyTo))") }
        if !message.to.isEmpty { headers.append("To: \(Self.encodeAddressList(message.to))") }
        if !message.cc.isEmpty { headers.append("Cc: \(Self.encodeAddressList(message.cc))") }
        if !message.bcc.isEmpty { headers.append("Bcc: \(Self.encodeAddressList(message.bcc))") }
        headers.append("Subject: \(Self.encodeHeaderText(message.subject))")
        headers.append("Date: \(Self.rfc5322Date(now()))")
        if let inReplyTo = message.inReplyTo { headers.append("In-Reply-To: \(inReplyTo)") }
        if !message.references.isEmpty { headers.append("References: \(message.references.joined(separator: " "))") }
        headers.append("MIME-Version: 1.0")

        let body = bodyEntity(for: message)
        var output = headers.joined(separator: "\r\n")
        output += "\r\n" + body
        return Data(output.utf8)
    }

    /// Returns the entity (its own headers + blank line + content) for the message body.
    private func bodyEntity(for message: OutgoingMessage) -> String {
        let textual: String
        if let html = message.htmlBody {
            let boundary = makeBoundary()
            textual = multipart("alternative", boundary: boundary, parts: [
                Self.textEntity(message.textBody, subtype: "plain"),
                Self.textEntity(html, subtype: "html"),
            ])
        } else {
            textual = Self.textEntity(message.textBody, subtype: "plain")
        }

        guard !message.attachments.isEmpty else { return textual }
        let boundary = makeBoundary()
        return multipart("mixed", boundary: boundary, parts: [textual] + message.attachments.map(Self.attachmentEntity))
    }

    private func multipart(_ subtype: String, boundary: String, parts: [String]) -> String {
        var result = "Content-Type: multipart/\(subtype); boundary=\"\(boundary)\"\r\n\r\n"
        for part in parts {
            result += "--\(boundary)\r\n\(part)\r\n"
        }
        result += "--\(boundary)--"
        return result
    }

    static func textEntity(_ text: String, subtype: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        return "Content-Type: text/\(subtype); charset=\"UTF-8\"\r\n"
            + "Content-Transfer-Encoding: base64\r\n\r\n"
            + wrappedBase64(Data(normalized.utf8))
    }

    static func attachmentEntity(_ attachment: OutgoingAttachment) -> String {
        let filename = attachment.filename.isEmpty ? "attachment" : attachment.filename
        return "Content-Type: \(attachment.mimeType); name=\(encodeParameterValue(filename))\r\n"
            + "Content-Disposition: attachment; \(encodeFilenameParameter(filename))\r\n"
            + "Content-Transfer-Encoding: base64\r\n\r\n"
            + wrappedBase64(attachment.data)
    }

    static func wrappedBase64(_ data: Data) -> String {
        data.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
    }

    // MARK: - Header encoding

    static func isPlainASCII(_ string: String) -> Bool {
        string.unicodeScalars.allSatisfy { $0.isASCII && $0.value >= 0x20 && $0.value != 0x7F }
    }

    /// RFC 2047 encoded-words (UTF-8, base64) for non-ASCII header text.
    public static func encodeHeaderText(_ text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        guard !isPlainASCII(singleLine) else { return singleLine }

        // Each encoded word must stay ≤ 75 characters: 45 bytes → 60 base64 chars + 12 overhead.
        var words: [String] = []
        var chunk = Data()
        for character in singleLine {
            let bytes = Data(String(character).utf8)
            if chunk.count + bytes.count > 45 {
                words.append("=?UTF-8?B?\(chunk.base64EncodedString())?=")
                chunk = Data()
            }
            chunk.append(bytes)
        }
        if !chunk.isEmpty { words.append("=?UTF-8?B?\(chunk.base64EncodedString())?=") }
        return words.joined(separator: "\r\n ")
    }

    static func encodeAddress(_ address: EmailAddress) -> String {
        guard let name = address.name else { return address.address }
        if isPlainASCII(name) {
            let needsQuotes = name.contains { "()<>[]:;@\\,.\"".contains($0) }
            let display = needsQuotes
                ? "\"\(name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
                : name
            return "\(display) <\(address.address)>"
        }
        return "\(encodeHeaderText(name)) <\(address.address)>"
    }

    static func encodeAddressList(_ addresses: [EmailAddress]) -> String {
        addresses.map(encodeAddress).joined(separator: ",\r\n ")
    }

    static func encodeParameterValue(_ value: String) -> String {
        if isPlainASCII(value) {
            return "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
        }
        return "\"\(encodeHeaderText(value).replacingOccurrences(of: "\r\n ", with: " "))\""
    }

    /// `filename="..."` for ASCII names, RFC 2231 `filename*=UTF-8''...` otherwise.
    static func encodeFilenameParameter(_ filename: String) -> String {
        if isPlainASCII(filename) {
            return "filename=\(encodeParameterValue(filename))"
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&+-.^_`|~")
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: allowed) ?? filename
        return "filename*=UTF-8''\(encoded)"
    }

    static func rfc5322Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
}
