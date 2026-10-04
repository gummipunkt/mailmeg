import Foundation

/// A calendar invitation attached to an email (`text/calendar`, usually `invite.ics`).
public struct CalendarInvitation: Hashable, Sendable {
    /// `REQUEST` (invitation or update), `CANCEL`, `REPLY` …
    public var method: String?
    public var uid: String
    public var summary: String
    public var location: String?
    public var description: String?
    public var start: Date?
    public var end: Date?
    public var isAllDay: Bool
    public var organizer: EmailAddress?
    public var attendees: [EmailAddress]

    public var isCancellation: Bool { method?.uppercased() == "CANCEL" }
    public var isReply: Bool { method?.uppercased() == "REPLY" }
}

/// Minimal iCalendar (RFC 5545) reader for invitations: the first VEVENT of a VCALENDAR.
public enum ICalendar {
    public static func invitation(from text: String) -> CalendarInvitation? {
        var method: String?
        var inEvent = false
        var depth = 0
        var properties: [(name: String, params: [String: String], value: String)] = []

        for line in unfold(text) {
            guard let property = parseProperty(line) else { continue }
            switch (property.name, property.value.uppercased()) {
            case ("BEGIN", "VEVENT") where !inEvent && properties.isEmpty:
                inEvent = true
                continue
            case ("BEGIN", _) where inEvent:
                depth += 1 // e.g. VALARM inside the event
                continue
            case ("END", "VEVENT") where inEvent && depth == 0:
                inEvent = false
            case ("END", _) where inEvent:
                depth = max(0, depth - 1)
                continue
            case ("METHOD", _) where !inEvent:
                method = property.value
            default:
                if inEvent && depth == 0 { properties.append(property) }
            }
        }

        func first(_ name: String) -> (params: [String: String], value: String)? {
            guard let match = properties.first(where: { $0.name == name }) else { return nil }
            return (params: match.params, value: match.value)
        }
        guard let uid = first("UID")?.value, !uid.isEmpty else { return nil }

        let start = first("DTSTART").map { parseDate($0.value, params: $0.params) }
        var end = first("DTEND").map { parseDate($0.value, params: $0.params) }?.date
        if end == nil, let startDate = start?.date, let duration = first("DURATION").flatMap({ parseDuration($0.value) }) {
            end = startDate.addingTimeInterval(duration)
        }
        return CalendarInvitation(
            method: method,
            uid: uid,
            summary: first("SUMMARY").map { unescape($0.value) } ?? "",
            location: first("LOCATION").map { unescape($0.value) }.flatMap { $0.isEmpty ? nil : $0 },
            description: first("DESCRIPTION").map { unescape($0.value) }.flatMap { $0.isEmpty ? nil : $0 },
            start: start?.date,
            end: end,
            isAllDay: start?.allDay ?? false,
            organizer: first("ORGANIZER").map { person($0.value, params: $0.params) },
            attendees: properties.filter { $0.name == "ATTENDEE" }.map { person($0.value, params: $0.params) }
        )
    }

    // MARK: - Lines and properties

    /// Splits into logical lines; lines starting with a space or tab continue the previous one.
    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n") {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                lines.append(raw)
            }
        }
        return lines
    }

    /// `NAME;PARAM=value;PARAM2="quoted:value":content` → name, parameters, content.
    static func parseProperty(_ line: String) -> (name: String, params: [String: String], value: String)? {
        var inQuotes = false
        var colon: String.Index?
        for index in line.indices {
            let character = line[index]
            if character == "\"" { inQuotes.toggle() }
            if character == ":" && !inQuotes { colon = index; break }
        }
        guard let colon else { return nil }
        let head = line[..<colon]
        let value = String(line[line.index(after: colon)...])
        var segments: [String] = []
        var current = ""
        inQuotes = false
        for character in head {
            if character == "\"" { inQuotes.toggle(); continue }
            if character == ";" && !inQuotes {
                segments.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        segments.append(current)
        guard let name = segments.first?.uppercased(), !name.isEmpty else { return nil }
        var params: [String: String] = [:]
        for segment in segments.dropFirst() {
            let pair = segment.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 { params[pair[0].uppercased()] = pair[1] }
        }
        return (name, params, value)
    }

    static func unescape(_ value: String) -> String {
        var output = ""
        var escaping = false
        for character in value {
            if escaping {
                switch character {
                case "n", "N": output.append("\n")
                default: output.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                output.append(character)
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Values

    /// `20261005`, `20261005T100000Z` or `20261005T100000` (with TZID or floating).
    static func parseDate(_ value: String, params: [String: String]) -> (date: Date?, allDay: Bool) {
        let digits = value.trimmingCharacters(in: .whitespaces)
        let isDateOnly = params["VALUE"]?.uppercased() == "DATE" || (digits.count == 8 && !digits.contains("T"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        if digits.hasSuffix("Z") {
            calendar.timeZone = TimeZone(identifier: "UTC")!
        } else if let tzid = params["TZID"], let zone = TimeZone(identifier: tzid) {
            calendar.timeZone = zone
        }
        func number(_ from: Int, _ length: Int) -> Int? {
            let chars = Array(digits)
            guard chars.count >= from + length else { return nil }
            return Int(String(chars[from..<from + length]))
        }
        guard let year = number(0, 4), let month = number(4, 2), let day = number(6, 2) else { return (nil, isDateOnly) }
        if isDateOnly {
            var local = Calendar(identifier: .gregorian)
            local.timeZone = .current
            return (local.date(from: DateComponents(year: year, month: month, day: day)), true)
        }
        let hour = number(9, 2) ?? 0
        let minute = number(11, 2) ?? 0
        let second = number(13, 2) ?? 0
        return (calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)), false)
    }

    /// `PT1H30M`, `P1D` … in seconds.
    static func parseDuration(_ value: String) -> TimeInterval? {
        var seconds: TimeInterval = 0
        var number = ""
        var sawDesignator = false
        for character in value.uppercased() {
            if character.isNumber {
                number.append(character)
                continue
            }
            let amount = Double(number) ?? 0
            number = ""
            switch character {
            case "W": seconds += amount * 604_800; sawDesignator = true
            case "D": seconds += amount * 86_400; sawDesignator = true
            case "H": seconds += amount * 3_600; sawDesignator = true
            case "M": seconds += amount * 60; sawDesignator = true
            case "S": seconds += amount; sawDesignator = true
            default: break
            }
        }
        return sawDesignator ? seconds : nil
    }

    /// `ORGANIZER;CN=Anna Becker:mailto:anna@example.com`
    static func person(_ value: String, params: [String: String]) -> EmailAddress {
        var address = value
        if address.lowercased().hasPrefix("mailto:") { address = String(address.dropFirst(7)) }
        return EmailAddress(name: params["CN"], address: address)
    }
}
