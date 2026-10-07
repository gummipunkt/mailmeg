import Foundation
import MailmegKit
import Observation
import SwiftUI

/// One event together with the account it belongs to. The calendar shows the events
/// of all accounts side by side.
@MainActor
struct CalendarEntry: Identifiable {
    let account: AccountSession
    let event: CalendarEvent

    nonisolated var id: String { Self.id(accountID: account.id, eventKey: event.key) }
    nonisolated static func id(accountID: String, eventKey: String) -> String { "\(accountID)#\(eventKey)" }

    var store: CalendarStore { account.calendar }
    var color: Color { store.color(for: event) }
    var canEdit: Bool { store.canEdit(event) }

    /// An invitation from someone else that has not been answered yet.
    var isAwaitingAnswer: Bool {
        event.myResponse == .needsAction && event.organizer?.isSelf != true
    }
}

/// What the calendar tab shows: the selected day, the view mode, the month in the mini
/// calendar and the search.
@MainActor
@Observable
final class CalendarViewState {
    enum Mode: String, CaseIterable {
        case day, week, month, agenda
    }

    private let accountsProvider: () -> [AccountSession]
    var accounts: [AccountSession] { accountsProvider() }
    /// Accounts whose calendar can be read (or is still being checked).
    var usableAccounts: [AccountSession] { accounts.filter { $0.calendar.isUsable } }

    private(set) var selectedDay: Date
    /// First day of the month shown in the mini calendar.
    private(set) var displayedMonth: Date
    /// The selected entry (`CalendarEntry.id`); its details are shown in a popover.
    var selectedEventID: String?
    var searchText = ""
    /// Bumped when an event selected from elsewhere should be scrolled into view.
    private(set) var revealRequest = 0
    var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }

    /// Days shown in the agenda.
    static let agendaLength = 14
    private static let modeKey = "calendar.mode"
    private let calendar = Calendar.current

    init(accounts: @escaping () -> [AccountSession]) {
        accountsProvider = accounts
        let today = Calendar.current.startOfDay(for: Date())
        selectedDay = today
        displayedMonth = Calendar.current.dateInterval(of: .month, for: today)?.start ?? today
        mode = Mode(rawValue: UserDefaults.standard.string(forKey: Self.modeKey) ?? "") ?? .week
    }

    // MARK: - Navigation

    func select(day: Date) {
        selectedDay = calendar.startOfDay(for: day)
        displayedMonth = calendar.dateInterval(of: .month, for: selectedDay)?.start ?? selectedDay
    }

    func goToToday() {
        select(day: Date())
        Task { await load() }
    }

    /// One day, week or month back (-1) or forward (+1).
    func step(_ direction: Int) {
        let unit: Calendar.Component
        switch mode {
        case .day: unit = .day
        case .week, .agenda: unit = .weekOfYear
        case .month: unit = .month
        }
        select(day: calendar.date(byAdding: unit, value: direction, to: selectedDay) ?? selectedDay)
        Task { await load() }
    }

    func stepMonth(_ direction: Int) {
        displayedMonth = calendar.date(byAdding: .month, value: direction, to: displayedMonth) ?? displayedMonth
        Task { await load() }
    }

    var isShowingToday: Bool {
        visibleDays.contains { calendar.isDateInToday($0) }
    }

    /// The days on screen: the selected day, its week, the month grid or the agenda.
    var visibleDays: [Date] {
        switch mode {
        case .month:
            return monthGrid
        case .agenda:
            return (0..<Self.agendaLength).compactMap { calendar.date(byAdding: .day, value: $0, to: selectedDay) }
        case .day:
            return [selectedDay]
        case .week:
            return week(of: selectedDay)
        }
    }

    func week(of day: Date) -> [Date] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: day) else { return [day] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }

    /// The 6×7 grid of the month in `displayedMonth`.
    var monthGrid: [Date] {
        let firstWeekday = calendar.component(.weekday, from: displayedMonth)
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: displayedMonth) ?? displayedMonth
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    func isInDisplayedMonth(_ day: Date) -> Bool {
        calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month)
    }

    // MARK: - Loading

    func load() async {
        let today = calendar.startOfDay(for: Date())
        // The next weeks too, for the invitations waiting for an answer.
        let days = visibleDays + monthGrid + [today, calendar.date(byAdding: .day, value: 30, to: today) ?? today]
        guard let first = days.min(), let last = days.max(),
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return }
        let interval = DateInterval(start: first, end: end)
        for account in usableAccounts {
            await account.calendar.ensureLoaded(interval)
        }
    }

    func refresh() async {
        for account in usableAccounts {
            await account.calendar.refresh()
        }
    }

    var isLoading: Bool { accounts.contains { $0.calendar.isLoading } }

    // MARK: - Events

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isSearching: Bool { !query.isEmpty }

    private func matches(_ event: CalendarEvent) -> Bool {
        let query = query
        guard !query.isEmpty else { return true }
        return [event.title, event.location ?? "", event.description ?? ""]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    /// Events of all accounts on `day`, all-day events first.
    func entries(on day: Date) -> [CalendarEntry] {
        accounts
            .flatMap { account in
                account.calendar.events(on: day).filter(matches).map { CalendarEntry(account: account, event: $0) }
            }
            .sorted(by: Self.order)
    }

    /// All loaded events matching the search, by day (for the results list).
    var searchResultDays: [Date] {
        guard isSearching else { return [] }
        let starts = accounts.flatMap { account in
            account.calendar.events.filter { !$0.isWorkingLocation && matches($0) }.compactMap(\.startDate)
        }
        return Array(Set(starts.map { calendar.startOfDay(for: $0) })).sorted()
    }

    /// Invitations in the coming weeks that still need an answer.
    var waitingForAnswer: [CalendarEntry] {
        let now = Date()
        return accounts
            .flatMap { account in
                account.calendar.events
                    .filter { ($0.endDate ?? now) > now && !$0.isCancelled }
                    .map { CalendarEntry(account: account, event: $0) }
            }
            .filter(\.isAwaitingAnswer)
            .sorted(by: Self.order)
    }

    func entry(id: String?) -> CalendarEntry? {
        guard let id else { return nil }
        for account in accounts {
            if let event = account.calendar.events.first(where: { CalendarEntry.id(accountID: account.id, eventKey: $0.key) == id }) {
                return CalendarEntry(account: account, event: event)
            }
        }
        return nil
    }

    /// Where the user works on `day`, if Google Calendar knows.
    func workingLocation(on day: Date) -> String? {
        accounts.lazy.compactMap { $0.calendar.workingLocation(on: day) }.first
    }

    func show(_ entry: CalendarEntry) {
        if let start = entry.event.startDate { select(day: start) }
        selectedEventID = entry.id
        revealSelectedEvent()
        Task { await load() }
    }

    func revealSelectedEvent() {
        revealRequest += 1
    }

    private static func order(_ lhs: CalendarEntry, _ rhs: CalendarEntry) -> Bool {
        if lhs.event.isAllDay != rhs.event.isAllDay { return lhs.event.isAllDay }
        return (lhs.event.startDate ?? .distantPast) < (rhs.event.startDate ?? .distantPast)
    }

    // MARK: - Labels

    /// "Sep – Okt", "2026" and "KW 41", as in the title of the calendar.
    var title: (main: String, year: String, week: String?) {
        let weekNumber = calendar.component(.weekOfYear, from: selectedDay)
        let weekLabel = tr("KW \(weekNumber)", "W\(weekNumber)")
        switch mode {
        case .month:
            return (displayedMonth.formatted(.dateTime.month(.wide)), displayedMonth.formatted(.dateTime.year()), nil)
        case .day:
            return (selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide)), selectedDay.formatted(.dateTime.year()), weekLabel)
        case .week, .agenda:
            let days = visibleDays
            guard let first = days.first, let last = days.last else { return ("", "", nil) }
            let main: String
            if calendar.isDate(first, equalTo: last, toGranularity: .month) {
                main = first.formatted(.dateTime.month(.wide))
            } else {
                main = "\(first.formatted(.dateTime.month(.abbreviated))) – \(last.formatted(.dateTime.month(.abbreviated)))"
            }
            return (main, last.formatted(.dateTime.year()), mode == .week ? weekLabel : nil)
        }
    }

    var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }
}
