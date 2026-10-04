import AppKit
import MailmegKit
import SwiftUI

// MARK: - Middle column: month and agenda

/// Mini month and the agenda of the coming days, in the place of the message list.
struct CalendarColumnView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Bindable var view: CalendarViewState

    private var store: CalendarStore { view.store }

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.isUsable {
                MiniMonthView(view: view)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                Divider().opacity(0.5)
                AgendaList(view: view)
            } else {
                Spacer()
            }
        }
        .navigationTitle(tr("Kalender", "Calendar"))
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label(tr("Aktualisieren", "Refresh"), systemImage: "arrow.clockwise")
                }
                .help(tr("Termine neu laden", "Reload events"))
            }
        }
        .glassBackground(.list)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            GlassCircleMenu(systemImage: "calendar.badge.checkmark", help: tr("Kalender auswählen", "Choose Calendars")) {
                if store.calendars.isEmpty {
                    Text(tr("Keine Kalender", "No Calendars"))
                }
                ForEach(store.calendars) { calendar in
                    Toggle(calendar.title, isOn: Binding(
                        get: { !store.hiddenCalendarIDs.contains(calendar.id) },
                        set: { store.setHidden(!$0, calendarID: calendar.id) }
                    ))
                }
            }
            .accessibilityIdentifier("calendar.calendars")

            Spacer(minLength: 4)
            VStack(spacing: 1) {
                Text(tr("Kalender", "Calendar"))
                    .font(.system(size: 15, weight: .bold))
                    .accessibilityIdentifier("calendar.title")
                Text(view.account.displayName ?? view.account.email)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            GlassCircleButton(systemImage: "plus", help: tr("Neuer Termin (⌥⌘N)", "New Event (⌥⌘N)")) {
                openWindow(value: EventDraft.new(accountID: view.account.id, day: view.selectedDay))
            }
            .disabled(!store.isUsable)
            .accessibilityIdentifier("calendar.new")
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

/// Small month grid with dots for days that have events.
struct MiniMonthView: View {
    @Bindable var view: CalendarViewState
    private let calendar = Calendar.current

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(view.monthTitle)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                IconButton(systemImage: "chevron.left", help: tr("Vorheriger Monat", "Previous Month"), tint: .primary) { view.stepMonth(-1) }
                IconButton(systemImage: "chevron.right", help: tr("Nächster Monat", "Next Month"), tint: .primary) { view.stepMonth(1) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(height: 16)
                }
                ForEach(view.monthGrid, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: view.selectedDay)
        let isToday = calendar.isDateInToday(day)
        let colors = Array(Set(view.store.events(on: day).map { view.store.color(for: $0) }).prefix(3))
        return Button {
            view.select(day: day)
            Task { await view.load() }
        } label: {
            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 11.5, weight: isToday || isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.white : isToday ? Color.accentColor : Color.primary)
                    .opacity(view.isInDisplayedMonth(day) || isSelected ? 1 : 0.35)
                    .frame(width: 24, height: 24)
                    .background {
                        if isSelected {
                            Circle().fill(Color.accentColor)
                        } else if isToday {
                            Circle().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.2)
                        }
                    }
                HStack(spacing: 2) {
                    ForEach(colors.indices, id: \.self) { index in
                        Circle().fill(colors[index]).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("calendar.day.\(CalendarDates.dayString(day))")
    }
}

/// The selected day and the six days after it, as a list.
private struct AgendaList: View {
    @Bindable var view: CalendarViewState
    private let calendar = Calendar.current

    private var days: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: view.selectedDay) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(days, id: \.self) { day in
                    let events = view.store.events(on: day)
                    Section {
                        if events.isEmpty {
                            Text(tr("Keine Termine", "No events"))
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }
                        ForEach(events, id: \.key) { event in
                            AgendaRow(event: event, color: view.store.color(for: event), day: day) {
                                view.select(day: day)
                                view.selectedEventID = event.key
                            }
                        }
                    } header: {
                        Text(CalendarFormat.dayHeading(day))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(calendar.isDateInToday(day) ? Color.accentColor : Color.secondary)
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                            .background(.ultraThinMaterial.opacity(0.9))
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .overlay {
            if view.store.isLoading && view.store.events.isEmpty {
                ProgressView()
            }
        }
    }
}

private struct AgendaRow: View {
    let event: CalendarEvent
    let color: Color
    let day: Date
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(CalendarFormat.title(event))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(CalendarFormat.timeRange(event, on: day))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    if let location = event.location, !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if let response = event.myResponse, response != .accepted {
                    RSVPBadge(status: response)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(isHovering ? 0.05 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("agenda.\(event.id)")
    }
}

// MARK: - Detail column: day and week timeline

struct CalendarTimelineView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Bindable var view: CalendarViewState

    private let hourHeight: CGFloat = 48
    private let gutter: CGFloat = 58
    private let calendar = Calendar.current

    private var store: CalendarStore { view.store }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionBar
            if store.isUsable {
                titleRow
                dayHeader
                allDayRow
                timeline
            } else {
                CalendarAccessView(store: store, account: view.account)
            }
        }
        .glassBackground(.canvas)
        .task(id: view.mode) { await view.load() }
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            GlassCircleButton(systemImage: "chevron.left", help: tr("Zurück", "Back")) { view.step(-1) }
                .accessibilityIdentifier("calendar.previous")
            GlassCapsuleButton(title: tr("Heute", "Today")) { view.goToToday() }
                .accessibilityIdentifier("calendar.today")
            GlassCircleButton(systemImage: "chevron.right", help: tr("Weiter", "Forward")) { view.step(1) }
                .accessibilityIdentifier("calendar.next")
            Spacer(minLength: 8)
            PillSwitch<CalendarViewState.Mode>(selection: $view.mode, options: [
                .init(value: .day, title: tr("Tag", "Day"), systemImage: nil, identifier: "calendar.mode.day"),
                .init(value: .week, title: tr("Woche", "Week"), systemImage: nil, identifier: "calendar.mode.week"),
            ])
            Spacer(minLength: 8)
            GlassCircleButton(systemImage: "plus", help: tr("Neuer Termin", "New Event")) {
                openWindow(value: EventDraft.new(accountID: view.account.id, day: view.selectedDay))
            }
            .disabled(!store.isUsable)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(view.timelineTitle)
                .font(.system(size: 24, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityIdentifier("calendar.timelineTitle")
            Text(view.weekSubtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if store.isLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
    }

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: gutter, height: 1)
            ForEach(view.visibleDays, id: \.self) { day in
                let isToday = calendar.isDateInToday(day)
                Button {
                    view.select(day: day)
                    view.mode = .day
                } label: {
                    HStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(view.mode == .day ? .wide : .abbreviated)))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(calendar.component(.day, from: day))")
                            .fontWeight(.bold)
                            .foregroundStyle(isToday ? Color.white : Color.primary)
                            .frame(minWidth: 22, minHeight: 22)
                            .background {
                                if isToday { Circle().fill(Color.accentColor) }
                            }
                    }
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tr("Diesen Tag anzeigen", "Show this day"))
            }
        }
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    @ViewBuilder
    private var allDayRow: some View {
        let days = view.visibleDays
        let allDay = days.map { day in store.events(on: day).filter(\.isAllDay) }
        if allDay.contains(where: { !$0.isEmpty }) {
            HStack(alignment: .top, spacing: 0) {
                Text(tr("ganztägig", "all-day"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: gutter - 6, alignment: .trailing)
                    .padding(.trailing, 6)
                    .padding(.top, 4)
                ForEach(days.indices, id: \.self) { index in
                    VStack(spacing: 2) {
                        ForEach(allDay[index], id: \.key) { event in
                            EventChip(event: event, color: store.color(for: event), isSelected: view.selectedEventID == event.key) {
                                view.selectedEventID = event.key
                            }
                            .popover(isPresented: popoverBinding(for: event), arrowEdge: .bottom) {
                                EventDetailView(event: event, store: store, account: view.account)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .padding(.horizontal, 2)
                }
            }
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .overlay(alignment: .bottom) { Divider().opacity(0.5) }
        }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    hourGrid
                    HStack(spacing: 0) {
                        ForEach(view.visibleDays, id: \.self) { day in
                            dayColumn(day)
                        }
                    }
                    .padding(.leading, gutter)
                    .padding(.trailing, 12)
                    nowLine
                }
                .frame(height: hourHeight * 24)
                .padding(.vertical, 8)
            }
            .onAppear { scrollToStart(proxy) }
            .onChange(of: view.selectedDay) { scrollToStart(proxy) }
        }
    }

    private func scrollToStart(_ proxy: ScrollViewProxy) {
        let firstEvent = view.visibleDays
            .flatMap { store.events(on: $0).filter { !$0.isAllDay } }
            .compactMap(\.startDate)
            .map { calendar.component(.hour, from: $0) }
            .min()
        // Start the morning in view (or earlier events), like Calendar does.
        var hour = min(firstEvent ?? 8, 8)
        if view.isShowingToday {
            hour = min(hour, calendar.component(.hour, from: Date()))
        }
        proxy.scrollTo("hour-\(min(max(hour - 1, 0), 18))", anchor: .top)
    }

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    Text(hourLabel(hour))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: gutter - 8, alignment: .trailing)
                        .offset(y: -6)
                        .opacity(hour == 0 ? 0 : 1)
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .id("hour-\(hour)")
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    @ViewBuilder
    private var nowLine: some View {
        if let index = view.visibleDays.firstIndex(where: { calendar.isDateInToday($0) }) {
            GeometryReader { proxy in
                let columns = CGFloat(view.visibleDays.count)
                let width = (proxy.size.width - gutter - 12) / columns
                let minutes = CGFloat(calendar.component(.hour, from: Date()) * 60 + calendar.component(.minute, from: Date()))
                HStack(spacing: 0) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Rectangle().fill(Color.red).frame(height: 1.5)
                }
                .frame(width: width + 4)
                .offset(x: gutter + width * CGFloat(index) - 4, y: minutes / 60 * hourHeight - 3.5)
            }
            .allowsHitTesting(false)
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let events = store.events(on: day).filter { !$0.isAllDay }
        let positioned = TimelineLayout.layout(events, on: day)
        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.primary.opacity(calendar.isDateInWeekend(day) ? 0.025 : 0))
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 1)
                ForEach(positioned) { item in
                    let laneWidth = (proxy.size.width - 4) / CGFloat(item.lanes)
                    EventBlock(event: item.event, color: store.color(for: item.event), isSelected: view.selectedEventID == item.event.key) {
                        view.selectedEventID = item.event.key
                    }
                    .frame(width: max(laneWidth - 2, 10), height: max((item.end - item.start) / 60 * hourHeight - 2, 18))
                    .popover(isPresented: popoverBinding(for: item.event), arrowEdge: .trailing) {
                        EventDetailView(event: item.event, store: store, account: view.account)
                    }
                    // Placed with padding (not offset), so the popover points at the block.
                    .padding(.leading, 3 + laneWidth * CGFloat(item.lane))
                    .padding(.top, item.start / 60 * hourHeight + 1)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func popoverBinding(for event: CalendarEvent) -> Binding<Bool> {
        Binding(
            get: { view.selectedEventID == event.key },
            set: { if !$0, view.selectedEventID == event.key { view.selectedEventID = nil } }
        )
    }
}

/// Places overlapping events side by side.
enum TimelineLayout {
    struct Item: Identifiable {
        let event: CalendarEvent
        /// Minutes since midnight, clipped to the day.
        let start: CGFloat
        let end: CGFloat
        var lane = 0
        var lanes = 1
        var id: String { event.key }
    }

    static func layout(_ events: [CalendarEvent], on day: Date) -> [Item] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        var items: [Item] = events.compactMap { event in
            guard let start = event.startDate, let end = event.endDate else { return nil }
            let from = max(0, CGFloat(start.timeIntervalSince(dayStart) / 60))
            let to = min(24 * 60, CGFloat(end.timeIntervalSince(dayStart) / 60))
            guard to > 0, from < 24 * 60 else { return nil }
            return Item(event: event, start: from, end: max(to, from + 15))
        }
        items.sort { $0.start == $1.start ? $0.end > $1.end : $0.start < $1.start }

        var result: [Item] = []
        var cluster: [Item] = []
        var laneEnds: [CGFloat] = []
        var clusterEnd: CGFloat = -1

        func flush() {
            let count = max(laneEnds.count, 1)
            result += cluster.map { item in
                var item = item
                item.lanes = count
                return item
            }
            cluster = []
            laneEnds = []
        }

        for var item in items {
            if item.start >= clusterEnd { flush() }
            if let free = laneEnds.firstIndex(where: { $0 <= item.start }) {
                item.lane = free
                laneEnds[free] = item.end
            } else {
                item.lane = laneEnds.count
                laneEnds.append(item.end)
            }
            clusterEnd = max(clusterEnd, item.end)
            cluster.append(item)
        }
        flush()
        return result
    }
}

private struct EventBlock: View {
    let event: CalendarEvent
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Rectangle().fill(color).frame(width: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(CalendarFormat.title(event))
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(2)
                    if let start = event.startDate {
                        Text(start.formatted(date: .omitted, time: .shortened) + (event.location.map { " · \($0)" } ?? ""))
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(color.opacity(isSelected ? 0.38 : 0.2), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(color.opacity(isSelected ? 0.9 : 0.35), lineWidth: isSelected ? 1.5 : 0.8)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .opacity(event.myResponse == .declined ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("event.\(event.id)")
    }
}

private struct EventChip: View {
    let event: CalendarEvent
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(CalendarFormat.title(event))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(isSelected ? 0.45 : 0.25), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("event.\(event.id)")
    }
}

// MARK: - Event details

struct EventDetailView: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEvent
    let store: CalendarStore
    let account: AccountSession
    @State private var current: CalendarEvent?
    @State private var isResponding = false

    private var shown: CalendarEvent { current ?? event }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Circle().fill(store.color(for: shown)).frame(width: 10, height: 10).padding(.top, 5)
                VStack(alignment: .leading, spacing: 2) {
                    Text(CalendarFormat.title(shown))
                        .font(.system(size: 16, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(CalendarFormat.fullRange(shown))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if let calendar = store.calendar(id: shown.calendarID) {
                        Text(calendar.title)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if let location = shown.location, !location.isEmpty {
                detailRow("mappin.and.ellipse") {
                    if let url = URL(string: "https://maps.apple.com/?q=\(location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")") {
                        Link(location, destination: url)
                    } else {
                        Text(location)
                    }
                }
            }
            if let meet = shown.hangoutLink, let url = URL(string: meet) {
                detailRow("video") {
                    Link(tr("Mit Google Meet teilnehmen", "Join with Google Meet"), destination: url)
                }
            }
            if let organizer = shown.organizer, !(organizer.isSelf ?? false) {
                detailRow("person.crop.circle") {
                    Text(tr("Organisiert von \(organizer.name)", "Organized by \(organizer.name)"))
                }
            }
            if let attendees = shown.attendees, !attendees.isEmpty {
                detailRow("person.2") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(attendees.prefix(8), id: \.self) { attendee in
                            HStack(spacing: 5) {
                                RSVPIcon(status: attendee.responseStatus.flatMap(RSVPStatus.init(rawValue:)) ?? .needsAction)
                                Text(attendee.isSelf == true ? tr("Du", "You") : attendee.name)
                                    .lineLimit(1)
                            }
                        }
                        if attendees.count > 8 {
                            Text(tr("und \(attendees.count - 8) weitere", "and \(attendees.count - 8) more"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let description = shown.description, !description.isEmpty {
                Text(HTMLText.plainText(fromHTML: description))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .textSelection(.enabled)
            }

            if shown.selfAttendee != nil, shown.organizer?.isSelf != true {
                RSVPButtons(current: shown.myResponse, isBusy: isResponding) { status in
                    respond(status)
                }
            }

            if let link = shown.htmlLink, let url = URL(string: link) {
                Link(destination: url) {
                    Label(tr("In Google Kalender öffnen", "Open in Google Calendar"), systemImage: "arrow.up.right.square")
                        .font(.system(size: 12))
                }
            }
        }
        .font(.system(size: 12.5))
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .accessibilityIdentifier("event.detail")
    }

    private func detailRow<Content: View>(_ systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            content()
        }
    }

    private func respond(_ status: RSVPStatus) {
        isResponding = true
        Task {
            defer { isResponding = false }
            do {
                current = try await store.respond(to: shown, with: status)
            } catch {
                model.present(error, account: account)
            }
        }
    }
}

/// Accept / maybe / decline.
struct RSVPButtons: View {
    let current: RSVPStatus?
    var isBusy = false
    let action: (RSVPStatus) -> Void

    var body: some View {
        HStack(spacing: 6) {
            button(.accepted, tr("Zusagen", "Accept"), "checkmark", "invitation.accept")
            button(.tentative, tr("Vielleicht", "Maybe"), "questionmark", "invitation.maybe")
            button(.declined, tr("Absagen", "Decline"), "xmark", "invitation.decline")
            if isBusy {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func button(_ status: RSVPStatus, _ title: String, _ systemImage: String, _ identifier: String) -> some View {
        let selected = current == status
        return Button {
            action(status)
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.85))
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background {
                    if selected {
                        Capsule().fill(RSVPIcon.color(status))
                    } else {
                        Capsule().fill(Color.primary.opacity(0.07))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(selected ? "selected" : "")
    }
}

struct RSVPIcon: View {
    let status: RSVPStatus

    static func color(_ status: RSVPStatus) -> Color {
        switch status {
        case .accepted: return Color(hex: "#188038")
        case .tentative: return Color(hex: "#e8a200")
        case .declined: return Color(hex: "#d93025")
        case .needsAction: return .secondary
        }
    }

    private var symbol: String {
        switch status {
        case .accepted: return "checkmark.circle.fill"
        case .tentative: return "questionmark.circle.fill"
        case .declined: return "xmark.circle.fill"
        case .needsAction: return "circle.dashed"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(Self.color(status))
            .font(.system(size: 11))
    }
}

private struct RSVPBadge: View {
    let status: RSVPStatus

    var body: some View {
        Text(CalendarFormat.responseLabel(status))
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(RSVPIcon.color(status))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RSVPIcon.color(status).opacity(0.14), in: Capsule())
    }
}

// MARK: - Access problems

/// Explains why the calendar is not available and how to fix it.
struct CalendarAccessView: View {
    @Environment(AppModel.self) private var model
    let store: CalendarStore
    let account: AccountSession

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Color.accentColor)
            switch store.access {
            case .needsConsent:
                Text(tr("Kalender verbinden", "Connect Calendar"))
                    .font(.system(size: 18, weight: .bold))
                Text(tr(
                    "MailMeG braucht einmalig deine Erlaubnis für Google Kalender. Du meldest dich dafür kurz neu bei Google an – deine E-Mails bleiben, wie sie sind.",
                    "MailMeG needs your permission for Google Calendar once. You’ll sign in to Google again briefly – your email stays as it is."
                ))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
                GlassCapsuleButton(title: tr("Kalender verbinden …", "Connect Calendar…"), systemImage: "link", isProminent: true) {
                    Task {
                        await model.signIn(loginHint: account.email)
                        model.showCalendar(accountID: account.email)
                    }
                }
                .accessibilityIdentifier("calendar.connect")
            case .apiDisabled:
                Text(tr("Google Calendar API ist nicht aktiviert", "Google Calendar API isn’t enabled"))
                    .font(.system(size: 18, weight: .bold))
                Text(tr(
                    "Aktiviere in deinem Google-Cloud-Projekt die „Google Calendar API“ (APIs & Dienste → Bibliothek), genau wie die Gmail API. Danach hier erneut versuchen.",
                    "Enable the “Google Calendar API” in your Google Cloud project (APIs & Services → Library), just like the Gmail API. Then try again here."
                ))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
                HStack(spacing: 8) {
                    GlassCapsuleButton(title: tr("Google Cloud öffnen", "Open Google Cloud"), systemImage: "arrow.up.right.square") {
                        NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/apis/library/calendar-json.googleapis.com")!)
                    }
                    GlassCapsuleButton(title: tr("Erneut versuchen", "Try Again"), isProminent: true) {
                        Task { await store.retry() }
                    }
                }
            case .failed(let message):
                Text(tr("Kalender konnte nicht geladen werden", "Couldn’t Load Calendar"))
                    .font(.system(size: 18, weight: .bold))
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 420)
                GlassCapsuleButton(title: tr("Erneut versuchen", "Try Again"), isProminent: true) {
                    Task { await store.retry() }
                }
            case .granted, .unknown:
                ProgressView()
            }
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sidebar: today

/// The rest of today's events across all accounts, at the foot of the sidebar.
struct TodayAgendaView: View {
    @Environment(AppModel.self) private var model

    private struct Entry: Identifiable {
        let account: AccountSession
        let event: CalendarEvent
        var id: String { "\(account.id)|\(event.key)" }
    }

    private var entries: [Entry] {
        model.accounts
            .filter { $0.calendar.access == .granted }
            .flatMap { account in account.calendar.upcomingToday.map { Entry(account: account, event: $0) } }
            .sorted { lhs, rhs in
                if lhs.event.isAllDay != rhs.event.isAllDay { return lhs.event.isAllDay }
                return (lhs.event.startDate ?? .distantPast) < (rhs.event.startDate ?? .distantPast)
            }
    }

    var body: some View {
        if model.accounts.contains(where: { $0.calendar.access == .granted }) {
            let items = entries
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(tr("Heute", "Today"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                if items.isEmpty {
                    Text(tr("Keine weiteren Termine", "No more events"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
                ForEach(items.prefix(4)) { entry in
                    Button {
                        model.showCalendar(accountID: entry.account.id, day: Date(), eventID: entry.event.key)
                    } label: {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(entry.account.calendar.color(for: entry.event))
                                .frame(width: 7, height: 7)
                            Text(entry.event.isAllDay ? tr("ganztägig", "all-day") : (entry.event.startDate?.formatted(date: .omitted, time: .shortened) ?? ""))
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 54, alignment: .leading)
                            Text(CalendarFormat.title(entry.event))
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if items.count > 4 {
                    Text(tr("+ \(items.count - 4) weitere", "+ \(items.count - 4) more"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(alignment: .top) { Divider().opacity(0.5) }
            .accessibilityIdentifier("sidebar.today")
        }
    }
}

// MARK: - Formatting

enum CalendarFormat {
    static func title(_ event: CalendarEvent) -> String {
        event.title.isEmpty ? tr("(Ohne Titel)", "(No title)") : event.title
    }

    /// "10:00 – 11:30", or "ganztägig" for all-day events.
    static func timeRange(_ event: CalendarEvent, on day: Date? = nil) -> String {
        if event.isAllDay { return tr("ganztägig", "all-day") }
        guard let start = event.startDate, let end = event.endDate else { return "" }
        return "\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
    }

    /// "Do., 8. Okt. · 10:00 – 11:30"
    static func fullRange(_ event: CalendarEvent) -> String {
        guard let start = event.startDate else { return "" }
        let calendar = Calendar.current
        if event.isAllDay {
            let lastDay = event.endDate.flatMap { calendar.date(byAdding: .day, value: -1, to: $0) } ?? start
            let first = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            if calendar.isDate(lastDay, inSameDayAs: start) {
                return "\(first) · \(tr("ganztägig", "all-day"))"
            }
            return "\(first) – \(lastDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
        }
        return "\(start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(timeRange(event))"
    }

    static func invitationRange(_ invitation: CalendarInvitation) -> String {
        guard let start = invitation.start else { return "" }
        let day = start.formatted(.dateTime.weekday(.wide).day().month(.wide))
        if invitation.isAllDay { return "\(day) · \(tr("ganztägig", "all-day"))" }
        let end = invitation.end.map { " – \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        return "\(day) · \(start.formatted(date: .omitted, time: .shortened))\(end)"
    }

    static func dayHeading(_ day: Date) -> String {
        let calendar = Calendar.current
        let date = day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        if calendar.isDateInToday(day) { return tr("Heute · \(date)", "Today · \(date)") }
        if calendar.isDateInTomorrow(day) { return tr("Morgen · \(date)", "Tomorrow · \(date)") }
        return date
    }

    static func responseLabel(_ status: RSVPStatus) -> String {
        switch status {
        case .accepted: return tr("Zugesagt", "Accepted")
        case .tentative: return tr("Vielleicht", "Maybe")
        case .declined: return tr("Abgesagt", "Declined")
        case .needsAction: return tr("Offen", "Not answered")
        }
    }
}

extension CalendarEvent {
    /// Unique across calendars (the same event can appear in several).
    var key: String { "\(calendarID ?? "")|\(id)" }
}
