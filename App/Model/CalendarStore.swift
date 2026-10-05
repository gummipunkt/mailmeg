import Foundation
import MailmegKit
import Observation
import SwiftUI

/// The Google Calendar of one account: its calendars and the events loaded so far.
@MainActor
@Observable
final class CalendarStore {
    enum Access: Equatable {
        /// Not known yet (tokens without scope information, or not loaded).
        case unknown
        case granted
        /// The account was signed in before MailMeG asked for calendar access.
        case needsConsent
        /// The Calendar API is not enabled in the Google Cloud project.
        case apiDisabled
        case failed(String)
    }

    let accountID: String
    let client: CalendarClient
    private(set) var access: Access
    private(set) var calendars: [GoogleCalendar] = []
    private(set) var events: [CalendarEvent] = []
    private(set) var isLoading = false
    /// Calendars the user switched off in MailMeG (stored per account).
    private(set) var hiddenCalendarIDs: Set<String>
    /// Days whose events have been loaded (midnight dates).
    private var loadedDays: Set<Date> = []
    private var calendarsLoaded = false
    private var lastRefresh = Date()

    init(accountID: String, client: CalendarClient, grantedScope: String?) {
        self.accountID = accountID
        self.client = client
        if grantedScope == nil {
            access = .unknown
        } else {
            access = CalendarClient.isGranted(scope: grantedScope) ? .granted : .needsConsent
        }
        hiddenCalendarIDs = Set(UserDefaults.standard.stringArray(forKey: Self.hiddenKey(accountID)) ?? [])
    }

    private static func hiddenKey(_ accountID: String) -> String { "calendar.hidden.\(accountID)" }

    var isUsable: Bool { access == .granted || access == .unknown }

    var visibleCalendars: [GoogleCalendar] {
        calendars.filter { !hiddenCalendarIDs.contains($0.id) }
    }

    var writableCalendars: [GoogleCalendar] {
        calendars.filter(\.isWritable).sorted { $0.isPrimary && !$1.isPrimary }
    }

    func calendar(id: String?) -> GoogleCalendar? {
        guard let id else { return nil }
        return calendars.first { $0.id == id } ?? (id == "primary" ? calendars.first(where: \.isPrimary) : nil)
    }

    func color(for event: CalendarEvent) -> Color {
        Self.color(hex: calendar(id: event.calendarID)?.backgroundColor)
    }

    static func color(hex: String?) -> Color {
        hex.map { Color(hex: $0) } ?? Palette.violet
    }

    func setHidden(_ hidden: Bool, calendarID: String) {
        if hidden { hiddenCalendarIDs.insert(calendarID) } else { hiddenCalendarIDs.remove(calendarID) }
        UserDefaults.standard.set(Array(hiddenCalendarIDs), forKey: Self.hiddenKey(accountID))
    }

    // MARK: - Loading

    /// Makes sure the events of all days in `interval` are loaded.
    func ensureLoaded(_ interval: DateInterval) async {
        guard isUsable else { return }
        if !calendarsLoaded {
            await loadCalendars()
            guard isUsable else { return }
        }
        let days = Self.days(in: interval)
        guard days.contains(where: { !loadedDays.contains($0) }) else { return }
        // Load in whole months around the request, so scrolling stays smooth and cheap.
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .month, for: interval.start)?.start ?? interval.start
        let monthAfter = calendar.date(byAdding: .month, value: 1, to: interval.end) ?? interval.end
        let end = calendar.dateInterval(of: .month, for: monthAfter)?.start ?? interval.end
        await load(DateInterval(start: start, end: max(end, interval.end)))
    }

    /// Starts over after an access problem was fixed (API enabled, permission granted).
    func retry() async {
        access = .unknown
        calendarsLoaded = false
        loadedDays = []
        await loadCalendars()
        let start = Calendar.current.startOfDay(for: Date())
        await ensureLoaded(DateInterval(start: start, end: start.addingTimeInterval(86_400 * 7)))
    }

    /// Background refresh while polling: at most every `maxAge` seconds.
    func refreshIfStale(maxAge: TimeInterval) async {
        guard calendarsLoaded, Date().timeIntervalSince(lastRefresh) > maxAge else { return }
        await refresh()
    }

    /// Reloads calendars and the events loaded so far (manual refresh).
    func refresh() async {
        guard isUsable else { return }
        lastRefresh = Date()
        let range = loadedDays.sorted()
        calendarsLoaded = false
        loadedDays = []
        await loadCalendars()
        if let first = range.first, let last = range.last {
            await load(DateInterval(start: first, end: Calendar.current.date(byAdding: .day, value: 1, to: last) ?? last))
        }
    }

    private func loadCalendars() async {
        do {
            calendars = try await client.calendars().sorted { lhs, rhs in
                if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            calendarsLoaded = true
            access = .granted
        } catch {
            handle(error)
        }
    }

    private func load(_ interval: DateInterval) async {
        isLoading = true
        defer { isLoading = false }
        let ids = calendars.map(\.id)
        let client = client
        do {
            let loaded = try await withThrowingTaskGroup(of: [CalendarEvent].self) { group in
                for id in ids {
                    group.addTask { try await client.events(calendarID: id, from: interval.start, to: interval.end) }
                }
                var all: [CalendarEvent] = []
                for try await events in group { all += events }
                return all
            }
            // Replace what was known for this range, keep the rest.
            events.removeAll { $0.overlaps(from: interval.start, to: interval.end) }
            events += loaded
            events.sort { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
            loadedDays.formUnion(Self.days(in: interval))
            access = .granted
        } catch {
            handle(error)
        }
    }

    private func handle(_ error: Error) {
        if let apiError = error as? GmailAPIError {
            if apiError.isInsufficientScope {
                access = .needsConsent
                return
            }
            if apiError.isAPIDisabled {
                access = .apiDisabled
                return
            }
        }
        access = .failed(error.localizedDescription)
    }

    static func days(in interval: DateInterval) -> [Date] {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: interval.start)
        var result: [Date] = []
        while day < interval.end {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    // MARK: - Queries

    /// Events of visible calendars overlapping [start, end), all-day events first.
    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        events
            .filter { event in
                !hiddenCalendarIDs.contains(event.calendarID ?? "") && event.overlaps(from: start, to: end)
            }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return (lhs.startDate ?? .distantPast) < (rhs.startDate ?? .distantPast)
            }
    }

    func events(on day: Date) -> [CalendarEvent] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return events(from: start, to: end)
    }

    /// The rest of today: events that have not ended yet.
    var upcomingToday: [CalendarEvent] {
        let now = Date()
        return events(on: now).filter { $0.isAllDay || ($0.endDate ?? now) > now }
    }

    // MARK: - Changes

    func respond(to event: CalendarEvent, with status: RSVPStatus) async throws -> CalendarEvent {
        let updated = try await client.respond(to: event, with: status)
        if let index = events.firstIndex(where: { $0.id == updated.id && $0.calendarID == updated.calendarID }) {
            events[index] = updated
        }
        return updated
    }

    func create(_ event: NewCalendarEvent, calendarID: String, notifyAttendees: Bool) async throws -> CalendarEvent {
        let created = try await client.insert(event, calendarID: calendarID, notifyAttendees: notifyAttendees)
        events.append(created)
        events.sort { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        return created
    }

    /// Whether MailMeG may change an event: the calendar must be writable, and invitations
    /// from someone else can only be answered, not edited.
    func canEdit(_ event: CalendarEvent) -> Bool {
        guard let calendar = calendar(id: event.calendarID), calendar.isWritable else { return false }
        if let organizer = event.organizer, organizer.isSelf != true, event.attendees?.isEmpty == false { return false }
        return true
    }

    func update(_ event: CalendarEvent, with patch: CalendarEventPatch, notifyAttendees: Bool) async throws -> CalendarEvent {
        let updated = try await client.update(event, with: patch, notifyAttendees: notifyAttendees)
        replace(updated)
        return updated
    }

    /// Moves an event by `seconds` (dragging it in the timeline), keeping its length.
    func move(_ event: CalendarEvent, by seconds: TimeInterval) async throws {
        guard seconds != 0, let start = event.startDate, let end = event.endDate else { return }
        // Show the new time right away, undo if Google refuses.
        var moved = event
        moved.start = EventDateTime(start.addingTimeInterval(seconds), allDay: event.isAllDay)
        moved.end = EventDateTime(end.addingTimeInterval(seconds), allDay: event.isAllDay)
        replace(moved)
        do {
            let patch = CalendarEventPatch(start: moved.start, end: moved.end)
            replace(try await client.update(event, with: patch, notifyAttendees: event.attendees?.isEmpty == false))
        } catch {
            replace(event)
            throw error
        }
    }

    func delete(_ event: CalendarEvent, notifyAttendees: Bool) async throws {
        try await client.delete(event, notifyAttendees: notifyAttendees)
        events.removeAll { $0.id == event.id && $0.calendarID == event.calendarID }
    }

    private func replace(_ event: CalendarEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id && $0.calendarID == event.calendarID }) {
            events[index] = event
        } else {
            events.append(event)
        }
        events.sort { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }

    /// The event behind an invitation email, looked up in the primary calendar.
    func event(forInvitation uid: String) async -> CalendarEvent? {
        guard isUsable else { return nil }
        do {
            let found = try await client.events(iCalUID: uid).first
            access = .granted
            return found
        } catch {
            handle(error)
            return nil
        }
    }
}
