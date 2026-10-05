import Foundation
import MailmegKit
import Observation

/// What the calendar screen shows: the selected day, day or week mode and the month
/// in the mini calendar.
@MainActor
@Observable
final class CalendarViewState {
    enum Mode: String, CaseIterable {
        case day, week, month
    }

    let account: AccountSession
    var store: CalendarStore { account.calendar }

    private(set) var selectedDay: Date
    /// First day of the month shown in the mini calendar.
    private(set) var displayedMonth: Date
    var selectedEventID: String?
    var mode: Mode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Self.modeKey) }
    }

    private static let modeKey = "calendar.mode"
    private let calendar = Calendar.current

    init(account: AccountSession) {
        self.account = account
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

    /// One day or one week back (-1) or forward (+1).
    func step(_ direction: Int) {
        let unit: Calendar.Component
        switch mode {
        case .day: unit = .day
        case .week: unit = .weekOfYear
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

    /// The days of the timeline: the selected day, or the week containing it.
    var visibleDays: [Date] {
        if mode == .month { return monthGrid }
        guard mode == .week, let week = calendar.dateInterval(of: .weekOfYear, for: selectedDay) else {
            return [selectedDay]
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
    }

    /// The 6×7 grid of the mini calendar for `displayedMonth`.
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
        let days = visibleDays + monthGrid
        guard let first = days.min(), let last = days.max(),
              let end = calendar.date(byAdding: .day, value: 1, to: last) else { return }
        await store.ensureLoaded(DateInterval(start: first, end: end))
    }

    // MARK: - Labels

    var timelineTitle: String {
        if mode == .month { return monthTitle }
        if mode == .day {
            return selectedDay.formatted(.dateTime.weekday(.wide).day().month(.wide))
        }
        let days = visibleDays
        guard let first = days.first, let last = days.last else { return "" }
        let sameMonth = calendar.isDate(first, equalTo: last, toGranularity: .month)
        let start = sameMonth ? first.formatted(.dateTime.day()) : first.formatted(.dateTime.day().month(.abbreviated))
        return "\(start) – \(last.formatted(.dateTime.day().month(.wide).year()))"
    }

    var monthTitle: String {
        displayedMonth.formatted(.dateTime.month(.wide).year())
    }

    var weekSubtitle: String {
        let week = calendar.component(.weekOfYear, from: selectedDay)
        return tr("Kalenderwoche \(week)", "Week \(week)")
    }
}
