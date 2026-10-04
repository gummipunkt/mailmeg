import XCTest
@testable import MailmegKit

final class CalendarTests: XCTestCase {
    // MARK: - iCalendar

    private let invite = """
    BEGIN:VCALENDAR\r
    PRODID:-//Google Inc//Google Calendar 70.9054//EN\r
    VERSION:2.0\r
    METHOD:REQUEST\r
    BEGIN:VEVENT\r
    DTSTART;TZID=Europe/Berlin:20261008T100000\r
    DTEND;TZID=Europe/Berlin:20261008T113000\r
    ORGANIZER;CN=Anna Becker:mailto:anna.becker@example.com\r
    UID:7kukuqrfedlm2f9t5vndeq0jl0@google.com\r
    ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;CN="Berger, Alex";X-NUM-GUESTS=0:mailto:alex@example.com\r
    SUMMARY:Design-Review\\, Q4\r
    LOCATION:Raum 3.14\\, Kantstraße 5\r
    DESCRIPTION:Bitte die Entwürfe mitbringen.\\nDanke!\r
      Bis Donnerstag.\r
    BEGIN:VALARM\r
    ACTION:DISPLAY\r
    DESCRIPTION:This is an event reminder\r
    TRIGGER:-P0DT0H30M0S\r
    END:VALARM\r
    END:VEVENT\r
    END:VCALENDAR\r
    """

    func testParsesGoogleInvitation() throws {
        let invitation = try XCTUnwrap(ICalendar.invitation(from: invite))
        XCTAssertEqual(invitation.method, "REQUEST")
        XCTAssertEqual(invitation.uid, "7kukuqrfedlm2f9t5vndeq0jl0@google.com")
        XCTAssertEqual(invitation.summary, "Design-Review, Q4")
        XCTAssertEqual(invitation.location, "Raum 3.14, Kantstraße 5")
        XCTAssertEqual(invitation.description, "Bitte die Entwürfe mitbringen.\nDanke! Bis Donnerstag.")
        XCTAssertFalse(invitation.isAllDay)
        XCTAssertEqual(invitation.organizer, EmailAddress(name: "Anna Becker", address: "anna.becker@example.com"))
        XCTAssertEqual(invitation.attendees, [EmailAddress(name: "Berger, Alex", address: "alex@example.com")])
        // 10:00 in Berlin (CEST, UTC+2) is 08:00 UTC.
        XCTAssertEqual(invitation.start, CalendarDates.parseRFC3339("2026-10-08T08:00:00Z"))
        XCTAssertEqual(invitation.end, CalendarDates.parseRFC3339("2026-10-08T09:30:00Z"))
    }

    func testAllDayUTCAndDuration() throws {
        let allDay = try XCTUnwrap(ICalendar.invitation(from: "BEGIN:VEVENT\nUID:a\nDTSTART;VALUE=DATE:20261010\nSUMMARY:Urlaub\nEND:VEVENT"))
        XCTAssertTrue(allDay.isAllDay)
        XCTAssertEqual(allDay.start, CalendarDates.parseDay("2026-10-10"))

        let utc = try XCTUnwrap(ICalendar.invitation(from: "METHOD:CANCEL\nBEGIN:VEVENT\nUID:b\nDTSTART:20261008T080000Z\nDURATION:PT1H30M\nEND:VEVENT"))
        XCTAssertTrue(utc.isCancellation)
        XCTAssertEqual(utc.start, CalendarDates.parseRFC3339("2026-10-08T08:00:00Z"))
        XCTAssertEqual(utc.end, CalendarDates.parseRFC3339("2026-10-08T09:30:00Z"))

        XCTAssertNil(ICalendar.invitation(from: "BEGIN:VEVENT\nSUMMARY:no uid\nEND:VEVENT"))
    }

    func testDateHelpers() {
        XCTAssertEqual(CalendarDates.parseRFC3339("2026-10-08T10:00:00+02:00"), CalendarDates.parseRFC3339("2026-10-08T08:00:00Z"))
        XCTAssertEqual(CalendarDates.parseRFC3339("2026-10-08T08:00:00.000Z"), CalendarDates.parseRFC3339("2026-10-08T08:00:00Z"))
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(CalendarDates.dayString(CalendarDates.parseDay("2026-02-28", timeZone: utc)!, timeZone: utc), "2026-02-28")

        let allDay = CalendarEvent(id: "e", summary: "Urlaub", start: EventDateTime(date: "2026-10-10"), end: EventDateTime(date: "2026-10-12"))
        XCTAssertTrue(allDay.isAllDay)
        XCTAssertTrue(allDay.overlaps(from: CalendarDates.parseDay("2026-10-11")!, to: CalendarDates.parseDay("2026-10-12")!))
        XCTAssertFalse(allDay.overlaps(from: CalendarDates.parseDay("2026-10-12")!, to: CalendarDates.parseDay("2026-10-13")!))
    }

    // MARK: - Messages

    func testMessageContentFindsInvitation() {
        let ics = Base64URL.encode(Data("BEGIN:VCALENDAR\nMETHOD:REQUEST\nBEGIN:VEVENT\nUID:x\nEND:VEVENT\nEND:VCALENDAR".utf8))
        let plain = MessagePart(partId: "0.0", mimeType: "text/plain", headers: [], body: MessagePartBody(size: 2, data: "SGk"))
        let calendar = MessagePart(partId: "0.1", mimeType: "text/calendar", headers: [MessageHeader(name: "Content-Type", value: "text/calendar; method=REQUEST")], body: MessagePartBody(size: 60, data: ics))
        let file = MessagePart(partId: "1", mimeType: "application/ics", filename: "invite.ics", headers: [], body: MessagePartBody(attachmentId: "att-ics", size: 60))
        let root = MessagePart(partId: "", mimeType: "multipart/mixed", parts: [
            MessagePart(partId: "0", mimeType: "multipart/alternative", parts: [plain, calendar]),
            file,
        ])
        let content = MessageContent(message: GmailMessage(id: "m1", threadId: "t1", payload: root))
        XCTAssertEqual(content.plainText, "Hi")
        XCTAssertEqual(content.calendar?.partID, "0.1", "The inline calendar part is preferred")
        XCTAssertNotNil(content.calendar?.inlineData)
        XCTAssertEqual(content.visibleAttachments.map(\.filename), ["invite.ics"])
    }

    // MARK: - API

    private func makeClient(_ api: MockTransport) -> CalendarClient {
        let config = GoogleOAuthConfig(clientID: "1234-abc.apps.googleusercontent.com")
        let tokens = TokenManager(
            tokens: OAuthTokens(accessToken: "token", refreshToken: "rt", expiresAt: Date().addingTimeInterval(3600)),
            oauth: GoogleOAuthClient(config: config, transport: api),
            onUpdate: { _ in }
        )
        return CalendarClient(api: GmailClient(tokens: tokens, transport: api, sleep: { _ in }))
    }

    func testEventsRequestAndDecoding() async throws {
        let api = MockTransport([{ request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(components.host, "www.googleapis.com")
            XCTAssertTrue(components.percentEncodedPath.hasPrefix("/calendar/v3/calendars/"))
            XCTAssertTrue(components.percentEncodedPath.hasSuffix("/events"))
            let items = components.queryItems ?? []
            XCTAssertEqual(items.first { $0.name == "singleEvents" }?.value, "true")
            XCTAssertEqual(items.first { $0.name == "orderBy" }?.value, "startTime")
            XCTAssertEqual(items.first { $0.name == "timeMin" }?.value, "2026-10-05T00:00:00Z")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
            return (200, Data("""
            {"items":[
              {"id":"e1","status":"confirmed","summary":"Standup","start":{"dateTime":"2026-10-05T09:00:00+02:00"},"end":{"dateTime":"2026-10-05T09:15:00+02:00"},
               "attendees":[{"email":"alex@example.com","self":true,"responseStatus":"tentative"},{"email":"anna@example.com","organizer":true,"responseStatus":"accepted"}]},
              {"id":"e2","status":"cancelled","start":{"date":"2026-10-06"},"end":{"date":"2026-10-07"}},
              {"id":"e3","summary":"Urlaub","start":{"date":"2026-10-06"},"end":{"date":"2026-10-08"}}
            ]}
            """.utf8))
        }])
        let from = CalendarDates.parseRFC3339("2026-10-05T00:00:00Z")!
        let events = try await makeClient(api).events(calendarID: "team@group.calendar.google.com", from: from, to: from.addingTimeInterval(7 * 86_400))
        XCTAssertEqual(events.map(\.id), ["e1", "e3"], "Cancelled occurrences are dropped")
        XCTAssertEqual(events[0].myResponse, .tentative)
        XCTAssertEqual(events[0].calendarID, "team@group.calendar.google.com")
        XCTAssertEqual(events[0].startDate, CalendarDates.parseRFC3339("2026-10-05T07:00:00Z"))
        XCTAssertTrue(events[1].isAllDay)
    }

    func testRespondPatchesOwnAttendee() async throws {
        let api = MockTransport([{ request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertTrue(request.url!.absoluteString.contains("/calendars/primary/events/e1?sendUpdates=all"))
            let json = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            let attendees = json?["attendees"] as? [[String: Any]] ?? []
            XCTAssertEqual(attendees.count, 2)
            XCTAssertEqual(attendees.first { $0["self"] as? Bool == true }?["responseStatus"] as? String, "accepted")
            XCTAssertEqual(attendees.first { $0["email"] as? String == "anna@example.com" }?["responseStatus"] as? String, "needsAction")
            return (200, Data(#"{"id":"e1","start":{"date":"2026-10-06"},"end":{"date":"2026-10-07"},"attendees":[{"email":"alex@example.com","self":true,"responseStatus":"accepted"}]}"#.utf8))
        }])
        let event = CalendarEvent(
            id: "e1", summary: "Review", start: EventDateTime(date: "2026-10-06"), end: EventDateTime(date: "2026-10-07"),
            attendees: [EventAttendee(email: "alex@example.com", isSelf: true), EventAttendee(email: "anna@example.com")],
            calendarID: "primary"
        )
        let updated = try await makeClient(api).respond(to: event, with: .accepted)
        XCTAssertEqual(updated.myResponse, .accepted)
    }

    func testInsertSendsInvitations() async throws {
        let api = MockTransport([{ request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(request.url!.absoluteString.hasSuffix("/calendars/primary/events?sendUpdates=all"))
            let json = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
            XCTAssertEqual(json?["summary"] as? String, "Kaffee")
            XCTAssertEqual((json?["start"] as? [String: Any])?["dateTime"] as? String, "2026-10-08T08:00:00Z")
            XCTAssertEqual((json?["attendees"] as? [[String: Any]])?.first?["email"] as? String, "anna@example.com")
            return (200, Data(#"{"id":"new","summary":"Kaffee","start":{"dateTime":"2026-10-08T08:00:00Z"},"end":{"dateTime":"2026-10-08T09:00:00Z"}}"#.utf8))
        }])
        let start = CalendarDates.parseRFC3339("2026-10-08T08:00:00Z")!
        let event = NewCalendarEvent(
            summary: "Kaffee",
            start: EventDateTime(dateTime: CalendarDates.rfc3339(start)),
            end: EventDateTime(dateTime: CalendarDates.rfc3339(start.addingTimeInterval(3600))),
            attendees: [EventAttendee(email: "anna@example.com")]
        )
        let created = try await makeClient(api).insert(event, calendarID: "primary", notifyAttendees: true)
        XCTAssertEqual(created.id, "new")
        XCTAssertEqual(created.calendarID, "primary")
    }

    func testScopeDetectionAndErrors() {
        XCTAssertFalse(CalendarClient.isGranted(scope: "https://www.googleapis.com/auth/gmail.modify"))
        XCTAssertFalse(CalendarClient.isGranted(scope: nil))
        XCTAssertTrue(CalendarClient.isGranted(scope: (["https://www.googleapis.com/auth/gmail.modify"] + CalendarClient.scopes).joined(separator: " ")))
        XCTAssertTrue(GmailAPIError(status: 403, message: "Request had insufficient authentication scopes.", reason: "insufficientPermissions").isInsufficientScope)
        XCTAssertTrue(GmailAPIError(status: 403, message: "Google Calendar API has not been used in project 123 before or it is disabled.", reason: "accessNotConfigured").isAPIDisabled)
    }
}
