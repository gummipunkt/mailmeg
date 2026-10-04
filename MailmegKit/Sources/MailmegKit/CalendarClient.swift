import Foundation

/// Typed wrapper around the Google Calendar API (v3). Shares authentication, token
/// refresh and retry handling with `GmailClient`.
public final class CalendarClient: Sendable {
    public static let readScope = "https://www.googleapis.com/auth/calendar.readonly"
    public static let eventsScope = "https://www.googleapis.com/auth/calendar.events"
    /// Scopes MailMeG asks for to show calendars and manage events.
    public static let scopes = [readScope, eventsScope]

    let api: GmailClient
    let base = "https://www.googleapis.com/calendar/v3/"

    public init(api: GmailClient) {
        self.api = api
    }

    /// True if the granted scopes (as stored with the tokens) cover the calendar.
    public static func isGranted(scope: String?) -> Bool {
        guard let scope else { return false }
        let granted = Set(scope.split(separator: " ").map(String.init))
        return scopes.allSatisfy { granted.contains($0) }
            || granted.contains("https://www.googleapis.com/auth/calendar")
    }

    // MARK: - Calendars

    public func calendars() async throws -> [GoogleCalendar] {
        struct Page: Decodable {
            let items: [GoogleCalendar]?
            let nextPageToken: String?
        }
        var result: [GoogleCalendar] = []
        var pageToken: String?
        repeat {
            var query = [URLQueryItem(name: "maxResults", value: "250")]
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: Page = try await api.perform(makeRequest("users/me/calendarList", query: query))
            result += page.items ?? []
            pageToken = page.nextPageToken
        } while pageToken != nil
        return result
    }

    // MARK: - Events

    /// Events (recurring ones expanded into single occurrences) overlapping [from, to).
    public func events(calendarID: String, from: Date, to: Date) async throws -> [CalendarEvent] {
        var query = [
            URLQueryItem(name: "timeMin", value: CalendarDates.rfc3339(from)),
            URLQueryItem(name: "timeMax", value: CalendarDates.rfc3339(to)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250"),
        ]
        return try await eventPages(calendarID: calendarID, query: &query)
    }

    /// Finds the event of an invitation by its iCalendar UID.
    public func events(iCalUID: String, calendarID: String = "primary") async throws -> [CalendarEvent] {
        var query = [URLQueryItem(name: "iCalUID", value: iCalUID)]
        return try await eventPages(calendarID: calendarID, query: &query)
    }

    private func eventPages(calendarID: String, query: inout [URLQueryItem]) async throws -> [CalendarEvent] {
        struct Page: Decodable {
            let items: [CalendarEvent]?
            let nextPageToken: String?
        }
        var result: [CalendarEvent] = []
        let baseQuery = query
        var pageToken: String?
        repeat {
            query = baseQuery
            if let pageToken { query.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            let page: Page = try await api.perform(makeRequest("calendars/\(Self.escape(calendarID))/events", query: query))
            result += (page.items ?? []).map { event in
                var event = event
                event.calendarID = calendarID
                return event
            }
            pageToken = page.nextPageToken
        } while pageToken != nil
        return result.filter { !$0.isCancelled }
    }

    /// Creates an event; with `notifyAttendees` Google sends the invitations.
    public func insert(_ event: NewCalendarEvent, calendarID: String, notifyAttendees: Bool) async throws -> CalendarEvent {
        var request = makeRequest(
            "calendars/\(Self.escape(calendarID))/events",
            query: [URLQueryItem(name: "sendUpdates", value: notifyAttendees ? "all" : "none")]
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(event)
        var created: CalendarEvent = try await api.perform(request)
        created.calendarID = calendarID
        return created
    }

    /// Answers an invitation: sets the user's own response and lets the organizer know.
    public func respond(to event: CalendarEvent, with status: RSVPStatus, calendarID: String = "primary") async throws -> CalendarEvent {
        struct Patch: Encodable { let attendees: [EventAttendee] }
        let attendees = (event.attendees ?? []).map { attendee -> EventAttendee in
            guard attendee.isSelf == true else { return attendee }
            var updated = attendee
            updated.responseStatus = status.rawValue
            return updated
        }
        var request = makeRequest(
            "calendars/\(Self.escape(event.calendarID ?? calendarID))/events/\(Self.escape(event.id))",
            query: [URLQueryItem(name: "sendUpdates", value: "all")]
        )
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Patch(attendees: attendees))
        var updated: CalendarEvent = try await api.perform(request)
        updated.calendarID = event.calendarID ?? calendarID
        return updated
    }

    // MARK: - Plumbing

    static func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/@#?"))) ?? component
    }

    private func makeRequest(_ path: String, query: [URLQueryItem]) -> URLRequest {
        var components = URLComponents(string: base + path)!
        if !query.isEmpty { components.queryItems = query }
        return URLRequest(url: components.url!)
    }
}

extension GmailAPIError {
    /// The account was signed in before MailMeG asked for calendar access.
    public var isInsufficientScope: Bool {
        status == 403 && (reason == "insufficientPermissions" || message.localizedCaseInsensitiveContains("insufficient authentication scopes"))
    }

    /// The Calendar API is not enabled in the user's Google Cloud project.
    public var isAPIDisabled: Bool {
        status == 403 && (reason == "accessNotConfigured" || message.contains("has not been used") || message.contains("is disabled"))
    }
}
