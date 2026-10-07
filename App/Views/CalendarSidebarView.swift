import MailmegKit
import SwiftUI

/// The sidebar of the calendar tab: month, the calendars of every account and the
/// invitations still waiting for an answer.
struct CalendarSidebarView: View {
    @Bindable var view: CalendarViewState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                MiniMonthView(view: view)
                ForEach(view.accounts) { account in
                    CalendarAccountSection(account: account)
                }
                WaitingForAnswerSection(view: view)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
        .safeAreaInset(edge: .top, spacing: 0) {
            SectionSwitch()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
        .glassBackground(.sidebar)
    }
}

// MARK: - Month

/// Small month grid with dots for days that have events; the selected week is marked.
struct MiniMonthView: View {
    @Bindable var view: CalendarViewState
    private let calendar = Calendar.current

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(view.monthTitle)
                    .font(.system(size: 13.5, weight: .bold))
                Spacer()
                IconButton(systemImage: "chevron.left", help: tr("Vorheriger Monat", "Previous Month"), tint: .secondary) { view.stepMonth(-1) }
                IconButton(systemImage: "chevron.right", help: tr("Nächster Monat", "Next Month"), tint: .secondary) { view.stepMonth(1) }
            }
            .padding(.leading, 4)
            .padding(.bottom, 4)
            HStack(spacing: 0) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 18)
            let grid = view.monthGrid
            VStack(spacing: 2) {
                ForEach(0..<(grid.count / 7), id: \.self) { row in
                    let days = Array(grid[(row * 7)..<(row * 7 + 7)])
                    let isSelectedWeek = view.mode == .week && days.contains { calendar.isDate($0, inSameDayAs: view.selectedDay) }
                    HStack(spacing: 0) {
                        ForEach(days, id: \.self) { day in
                            dayCell(day)
                        }
                    }
                    .background {
                        if isSelectedWeek {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: view.selectedDay)
        let isToday = calendar.isDateInToday(day)
        let colors = Array(Set(view.entries(on: day).map(\.color)).prefix(3))
        return Button {
            view.select(day: day)
            Task { await view.load() }
        } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 12, weight: isToday || isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.white : isToday ? Color.accentColor : Color.primary)
                    .opacity(view.isInDisplayedMonth(day) || isSelected ? 1 : 0.35)
                    .frame(width: 26, height: 24)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(LinearGradient(colors: [Palette.periwinkle, Palette.violet], startPoint: .top, endPoint: .bottom))
                        }
                    }
                HStack(spacing: 2) {
                    ForEach(colors.indices, id: \.self) { index in
                        Circle().fill(colors[index]).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
                .opacity(view.isInDisplayedMonth(day) ? 1 : 0.4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("calendar.day.\(CalendarDates.dayString(day))")
    }
}

// MARK: - Calendars

/// The calendars of one account, each with a check to show or hide it.
private struct CalendarAccountSection: View {
    @Environment(AppModel.self) private var model
    let account: AccountSession

    private var store: CalendarStore { account.calendar }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.isDemo ? tr("Demo-Konto", "Demo account") : account.email)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .padding(.leading, 4)
                .padding(.bottom, 4)
            switch store.access {
            case .needsConsent:
                hint(tr("Für diesen Kalender fehlt noch deine Erlaubnis.", "This calendar still needs your permission."),
                     action: tr("Kalender verbinden …", "Connect Calendar…")) {
                    Task {
                        await model.signIn(loginHint: account.email)
                        model.showCalendar()
                    }
                }
            case .apiDisabled:
                hint(tr("Die Google Calendar API ist im Cloud-Projekt nicht aktiviert.", "The Google Calendar API isn’t enabled in the Cloud project."),
                     action: tr("Erneut versuchen", "Try Again")) {
                    Task { await store.retry() }
                }
            case .failed(let message):
                hint(message, action: tr("Erneut versuchen", "Try Again")) {
                    Task { await store.retry() }
                }
            case .granted, .unknown:
                if store.calendars.isEmpty {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 6)
                }
                ForEach(store.calendars) { calendar in
                    CalendarToggleRow(calendar: calendar, store: store)
                }
            }
        }
    }

    private func hint(_ text: String, action title: String, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(title, action: perform)
                .buttonStyle(.link)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 4)
    }
}

private struct CalendarToggleRow: View {
    let calendar: GoogleCalendar
    let store: CalendarStore
    @State private var isHovering = false

    private var isVisible: Bool { !store.hiddenCalendarIDs.contains(calendar.id) }

    var body: some View {
        Button {
            store.setHidden(isVisible, calendarID: calendar.id)
        } label: {
            HStack(spacing: 9) {
                let color = CalendarStore.color(hex: calendar.backgroundColor)
                Group {
                    if isVisible {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, color)
                    } else {
                        Image(systemName: "circle")
                            .foregroundStyle(color)
                    }
                }
                .font(.system(size: 15))
                Text(calendar.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isVisible ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !calendar.isWritable {
                    Image(systemName: "lock")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .help(tr("Nur lesen", "Read only"))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.06 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isVisible ? tr("Kalender ausblenden", "Hide calendar") : tr("Kalender einblenden", "Show calendar"))
        .accessibilityIdentifier("calendar.toggle.\(calendar.id)")
        .accessibilityValue(isVisible ? "on" : "off")
    }
}

// MARK: - Invitations

/// Invitations in the coming weeks that have not been answered yet.
private struct WaitingForAnswerSection: View {
    @Bindable var view: CalendarViewState

    var body: some View {
        let entries = view.waitingForAnswer
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(tr("Wartet auf deine Antwort", "Waiting for your answer"))
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.leading, 4)
                ForEach(entries.prefix(6)) { entry in
                    WaitingCard(entry: entry) {
                        if view.mode == .month { view.mode = .week }
                        view.show(entry)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("calendar.waiting")
        }
    }
}

private struct WaitingCard: View {
    let entry: CalendarEntry
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(CalendarFormat.title(entry.event))
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(when)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.cardFill.opacity(isHovering ? 1 : 0.85))
                    .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("waiting.\(entry.event.id)")
    }

    private var when: String {
        guard let start = entry.event.startDate else { return "" }
        if entry.event.isAllDay {
            return start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
}
