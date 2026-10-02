import Foundation

/// A structured MIME header value such as `text/plain; charset="utf-8"`.
public struct HeaderValue: Equatable, Sendable {
    public var value: String
    public var parameters: [String: String]

    public init(_ raw: String) {
        let segments = HeaderValue.splitSegments(raw)
        value = (segments.first ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        var parameters: [String: String] = [:]
        for segment in segments.dropFirst() {
            guard let equals = segment.firstIndex(of: "=") else { continue }
            let key = segment[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            var parameterValue = segment[segment.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if parameterValue.hasPrefix("\""), parameterValue.hasSuffix("\""), parameterValue.count >= 2 {
                parameterValue = String(parameterValue.dropFirst().dropLast())
            }
            parameters[key] = parameterValue
        }
        self.parameters = parameters
    }

    public subscript(parameter: String) -> String? { parameters[parameter.lowercased()] }

    private static func splitSegments(_ raw: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var inQuotes = false
        for character in raw {
            if character == "\"" { inQuotes.toggle() }
            if character == ";", !inQuotes {
                segments.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        segments.append(current)
        return segments
    }
}

enum TextDecoding {
    /// Decodes a message body from the Gmail API. Gmail hands out text parts already
    /// converted to UTF-8, even when the original header still says e.g. ISO-8859-1, so
    /// valid UTF-8 wins; the declared charset is only the fallback for unconverted bytes.
    static func body(from data: Data, charset: String?) -> String {
        let declared = charset?.lowercased() ?? ""
        if !declared.hasPrefix("utf-16"), !declared.hasPrefix("utf-32"), let string = String(data: data, encoding: .utf8) {
            return string
        }
        return string(from: data, charset: charset)
    }

    /// Decodes bytes in their declared charset (raw sources, RFC 2047 words).
    static func string(from data: Data, charset: String?) -> String {
        if let charset {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEncoding))
                if let string = String(data: data, encoding: encoding) {
                    return string
                }
            }
        }
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
    }
}
