import Foundation

/// One calendar from the user's calendar list (Google Calendar API v3).
public struct GoogleCalendar: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let summary: String?
    public let summaryOverride: String?
    public let backgroundColor: String?
    public let foregroundColor: String?
    public let primary: Bool?
    public let selected: Bool?
    public let accessRole: String?
    public let timeZone: String?

    public init(id: String, summary: String?, summaryOverride: String? = nil, backgroundColor: String? = nil, foregroundColor: String? = nil,
                primary: Bool? = nil, selected: Bool? = nil, accessRole: String? = "owner", timeZone: String? = nil) {
        self.id = id
        self.summary = summary
        self.summaryOverride = summaryOverride
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.primary = primary
        self.selected = selected
        self.accessRole = accessRole
        self.timeZone = timeZone
    }

    public var title: String { summaryOverride ?? summary ?? id }
    public var isPrimary: Bool { primary == true }
    /// Events can be created in calendars the user owns or may edit.
    public var isWritable: Bool { accessRole == "owner" || accessRole == "writer" }
}

/// Start or end of an event: `date` for all-day events, `dateTime` (RFC 3339) otherwise.
public struct EventDateTime: Codable, Hashable, Sendable {
    public var date: String?
    public var dateTime: String?
    public var timeZone: String?

    public init(date: String? = nil, dateTime: String? = nil, timeZone: String? = nil) {
        self.date = date
        self.dateTime = dateTime
        self.timeZone = timeZone
    }

    /// Builds the API value for a point in time (or a day, for all-day events).
    public init(_ value: Date, allDay: Bool, timeZone: TimeZone = .current) {
        if allDay {
            self.init(date: CalendarDates.dayString(value, timeZone: timeZone))
        } else {
            self.init(dateTime: CalendarDates.rfc3339(value), timeZone: timeZone.identifier)
        }
    }

    public var isAllDay: Bool { date != nil && dateTime == nil }

    /// The moment this value stands for; all-day dates resolve to local midnight.
    public func resolved(in timeZone: TimeZone = .current) -> Date? {
        if let dateTime { return CalendarDates.parseRFC3339(dateTime) }
        if let date { return CalendarDates.parseDay(date, timeZone: timeZone) }
        return nil
    }
}

public struct EventAttendee: Codable, Hashable, Sendable {
    public var email: String?
    public var displayName: String?
    /// `needsAction`, `declined`, `tentative` or `accepted`.
    public var responseStatus: String?
    public var isSelf: Bool?
    public var organizer: Bool?
    public var optional: Bool?

    enum CodingKeys: String, CodingKey {
        case email, displayName, responseStatus, organizer, optional
        case isSelf = "self"
    }

    public init(email: String?, displayName: String? = nil, responseStatus: String? = "needsAction", isSelf: Bool? = nil, organizer: Bool? = nil, optional: Bool? = nil) {
        self.email = email
        self.displayName = displayName
        self.responseStatus = responseStatus
        self.isSelf = isSelf
        self.organizer = organizer
        self.optional = optional
    }

    public var name: String { displayName ?? email ?? "" }
}

public struct EventPerson: Codable, Hashable, Sendable {
    public var email: String?
    public var displayName: String?
    public var isSelf: Bool?

    enum CodingKeys: String, CodingKey {
        case email, displayName
        case isSelf = "self"
    }

    public init(email: String?, displayName: String? = nil, isSelf: Bool? = nil) {
        self.email = email
        self.displayName = displayName
        self.isSelf = isSelf
    }

    public var name: String { displayName ?? email ?? "" }
}

/// The answer to an invitation.
public enum RSVPStatus: String, CaseIterable, Sendable {
    case accepted, tentative, declined, needsAction
}

/// One event (or one occurrence of a recurring event).
public struct CalendarEvent: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var status: String?
    public var summary: String?
    public var description: String?
    public var location: String?
    public var htmlLink: String?
    public var hangoutLink: String?
    public var start: EventDateTime
    public var end: EventDateTime
    public var attendees: [EventAttendee]?
    public var organizer: EventPerson?
    public var iCalUID: String?
    public var recurringEventId: String?
    /// Not part of the API: the calendar the event was loaded from.
    public var calendarID: String?

    public init(id: String, summary: String?, start: EventDateTime, end: EventDateTime, location: String? = nil, description: String? = nil,
                attendees: [EventAttendee]? = nil, organizer: EventPerson? = nil, iCalUID: String? = nil, htmlLink: String? = nil,
                hangoutLink: String? = nil, status: String? = "confirmed", calendarID: String? = nil) {
        self.id = id
        self.summary = summary
        self.start = start
        self.end = end
        self.location = location
        self.description = description
        self.attendees = attendees
        self.organizer = organizer
        self.iCalUID = iCalUID
        self.htmlLink = htmlLink
        self.hangoutLink = hangoutLink
        self.status = status
        self.calendarID = calendarID
    }

    /// The trimmed title; empty for events without one (the app shows a placeholder).
    public var title: String {
        summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public var isAllDay: Bool { start.isAllDay }
    public var isCancelled: Bool { status == "cancelled" }
    public var startDate: Date? { start.resolved() }

    /// End of the event; all-day ends are exclusive (the day after the last day).
    public var endDate: Date? {
        if let end = end.resolved() { return end }
        return startDate.map { $0.addingTimeInterval(isAllDay ? 86_400 : 3_600) }
    }

    /// The signed-in user's entry in the attendee list, if they were invited.
    public var selfAttendee: EventAttendee? { attendees?.first { $0.isSelf == true } }

    public var myResponse: RSVPStatus? {
        selfAttendee?.responseStatus.flatMap(RSVPStatus.init(rawValue:))
    }

    /// True if the event overlaps the half-open interval [from, to).
    public func overlaps(from: Date, to: Date) -> Bool {
        guard let start = startDate, let end = endDate else { return false }
        return start < to && max(end, start.addingTimeInterval(1)) > from
    }
}

/// Changes to an existing event; only the fields that are set are sent.
public struct CalendarEventPatch: Encodable, Sendable {
    public var summary: String?
    public var description: String?
    public var location: String?
    public var start: EventDateTime?
    public var end: EventDateTime?
    public var attendees: [EventAttendee]?

    public init(summary: String? = nil, description: String? = nil, location: String? = nil,
                start: EventDateTime? = nil, end: EventDateTime? = nil, attendees: [EventAttendee]? = nil) {
        self.summary = summary
        self.description = description
        self.location = location
        self.start = start
        self.end = end
        self.attendees = attendees
    }
}

/// A new event to insert (only the fields MailMeG sets).
public struct NewCalendarEvent: Encodable, Sendable {
    public var summary: String
    public var description: String?
    public var location: String?
    public var start: EventDateTime
    public var end: EventDateTime
    public var attendees: [EventAttendee]?

    public init(summary: String, start: EventDateTime, end: EventDateTime, location: String? = nil, description: String? = nil, attendees: [EventAttendee]? = nil) {
        self.summary = summary
        self.start = start
        self.end = end
        self.location = location
        self.description = description
        self.attendees = attendees
    }
}

/// Date helpers for the Calendar API formats.
public enum CalendarDates {
    public static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    public static func parseRFC3339(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    /// `yyyy-MM-dd` → midnight of that day in `timeZone`.
    public static func parseDay(_ string: String, timeZone: TimeZone = .current) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    public static func dayString(_ date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
