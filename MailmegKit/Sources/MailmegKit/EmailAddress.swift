import Foundation

public struct EmailAddress: Hashable, Codable, Sendable {
    public var name: String?
    public var address: String

    public init(name: String? = nil, address: String) {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = (trimmedName?.isEmpty ?? true) ? nil : trimmedName
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var displayName: String { name ?? address }

    /// Value suitable for user-facing text fields, e.g. `Jane Doe <jane@example.com>`.
    public var formatted: String {
        guard let name else { return address }
        let needsQuotes = name.contains { ",;<>@\"()[]:\\.".contains($0) }
        let quoted = needsQuotes ? "\"\(name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\"" : name
        return "\(quoted) <\(address)>"
    }

    /// Parses an address list such as `"Doe, Jane" <jane@example.com>, bob@example.com`.
    public static func parseList(_ string: String) -> [EmailAddress] {
        splitList(string).compactMap(parse)
    }

    public static func parse(_ string: String) -> EmailAddress? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let open = trimmed.lastIndex(of: "<"),
           let close = trimmed[open...].firstIndex(of: ">") {
            let address = String(trimmed[trimmed.index(after: open)..<close])
            var name = String(trimmed[..<open]).trimmingCharacters(in: .whitespaces)
            if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 {
                name = String(name.dropFirst().dropLast())
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
            }
            guard !address.isEmpty else { return nil }
            return EmailAddress(name: name, address: address)
        }
        return EmailAddress(address: trimmed)
    }

    /// Splits on commas/semicolons that are not inside quotes or angle brackets.
    static func splitList(_ string: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var inAngle = false
        var escaped = false

        for character in string {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            switch character {
            case "\\" where inQuotes:
                escaped = true
                current.append(character)
            case "\"":
                inQuotes.toggle()
                current.append(character)
            case "<" where !inQuotes:
                inAngle = true
                current.append(character)
            case ">" where !inQuotes:
                inAngle = false
                current.append(character)
            case ",", ";":
                if inQuotes || inAngle {
                    current.append(character)
                } else {
                    parts.append(current)
                    current = ""
                }
            default:
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }
}
