import Foundation

/// Helpers for showing a message's original source and headers.
public enum RawMessage {
    /// The source as text (UTF-8, falling back to Latin-1 for 8-bit messages).
    public static func text(from data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
    }

    /// The header block of a message, unfolded (continuation lines joined), in original order.
    /// Encoded words (`=?UTF-8?B?…?=`) are decoded for display.
    public static func headers(from source: String) -> [MessageHeader] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let headerBlock = normalized.components(separatedBy: "\n\n").first ?? normalized
        var headers: [MessageHeader] = []
        var name: String?
        var value = ""

        func flush() {
            if let name {
                headers.append(MessageHeader(name: name, value: decodeEncodedWords(value.trimmingCharacters(in: .whitespaces))))
            }
        }

        for line in headerBlock.components(separatedBy: "\n") {
            if line.first == " " || line.first == "\t" {
                value += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                flush()
                name = String(line[..<colon])
                value = String(line[line.index(after: colon)...])
            }
        }
        flush()
        return headers
    }

    /// Decodes RFC 2047 encoded words (B and Q encoding).
    public static func decodeEncodedWords(_ text: String) -> String {
        guard text.contains("=?") else { return text }
        let pattern = #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var output = ""
        var location = 0
        var previousWasEncoded = false
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let between = ns.substring(with: NSRange(location: location, length: match.range.location - location))
            // Whitespace between two encoded words is not displayed (RFC 2047 §6.2).
            if !(previousWasEncoded && between.trimmingCharacters(in: .whitespaces).isEmpty) {
                output += between
            }
            let charset = ns.substring(with: match.range(at: 1))
            let encoding = ns.substring(with: match.range(at: 2)).uppercased()
            let payload = ns.substring(with: match.range(at: 3))
            var data: Data?
            if encoding == "B" {
                data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters)
            } else {
                data = quotedPrintableHeader(payload)
            }
            if let data {
                output += TextDecoding.string(from: data, charset: charset)
            } else {
                output += ns.substring(with: match.range)
            }
            location = match.range.location + match.range.length
            previousWasEncoded = true
        }
        output += ns.substring(from: location)
        return output
    }

    private static func quotedPrintableHeader(_ text: String) -> Data {
        var bytes: [UInt8] = []
        let chars = Array(text.replacingOccurrences(of: "_", with: " ").utf8)
        var index = 0
        while index < chars.count {
            if chars[index] == UInt8(ascii: "="), index + 2 < chars.count,
               let value = UInt8(String(decoding: chars[(index + 1)...(index + 2)], as: UTF8.self), radix: 16) {
                bytes.append(value)
                index += 3
            } else {
                bytes.append(chars[index])
                index += 1
            }
        }
        return Data(bytes)
    }
}
