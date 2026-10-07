import AppKit
import MailmegKit
import SwiftUI

// MARK: - Calendar tab

/// The calendar next to the sidebar: title and controls on top, the week, day, month or
/// agenda below on a card.
struct CalendarMainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Bindable var view: CalendarViewState
    @State private var showsSearch = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.cardFill.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.hairline.opacity(0.45), lineWidth: 0.8)
                )
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
        }
        .navigationTitle(tr("Kalender", "Calendar"))
        .glassBackground(.canvas)
        .task(id: view.mode) { await view.load() }
    }

    @ViewBuilder
    private var content: some View {
        if view.usableAccounts.isEmpty, let account = view.accounts.first {
            CalendarAccessView(store: account.calendar, account: account)
        } else if view.isSearching {
            let days = view.searchResultDays
            if days.isEmpty {
                ContentUnavailableView.search(text: view.searchText)
            } else {
                AgendaList(view: view, days: days, showsEmptyDays: false)
            }
        } else {
            switch view.mode {
            case .day, .week:
                CalendarWeekView(view: view)
            case .month:
                MonthGridView(view: view)
            case .agenda:
                AgendaList(view: view, days: view.visibleDays, showsEmptyDays: true)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            title
                .layoutPriority(-1)
            GlassCapsuleButton(title: tr("Heute", "Today")) { view.goToToday() }
                .accessibilityIdentifier("calendar.today")
            stepper
            if view.isLoading {
                ProgressView().controlSize(.small)
            }
            Spacer(minLength: 8)
            PillSwitch<CalendarViewState.Mode>(selection: $view.mode, options: [
                .init(value: .day, title: tr("Tag", "Day"), systemImage: nil, identifier: "calendar.mode.day"),
                .init(value: .week, title: tr("Woche", "Week"), systemImage: nil, identifier: "calendar.mode.week"),
                .init(value: .month, title: tr("Monat", "Month"), systemImage: nil, identifier: "calendar.mode.month"),
                .init(value: .agenda, title: tr("Agenda", "Agenda"), systemImage: nil, identifier: "calendar.mode.agenda"),
            ])
            newEventButton
            search
        }
        .padding(.leading, 22)
        .padding(.trailing, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var title: some View {
        let parts = view.title
        return HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(parts.main)
                .font(.system(size: 22, weight: .bold))
            Text(parts.year)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(.tertiary)
            if let week = parts.week {
                Text(week)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("calendar.title")
    }

    /// Back and forward in one capsule.
    private var stepper: some View {
        HStack(spacing: 0) {
            stepButton("chevron.left", help: tr("Zurück", "Back"), identifier: "calendar.previous") { view.step(-1) }
            Divider().frame(height: 14).opacity(0.6)
            stepButton("chevron.right", help: tr("Weiter", "Forward"), identifier: "calendar.next") { view.step(1) }
        }
        .background(.ultraThinMaterial, in: Capsule())
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        .fixedSize()
    }

    private func stepButton(_ systemImage: String, help: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.8))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityIdentifier(identifier)
    }

    private var newEventButton: some View {
        Button {
            openWindow(value: model.newEventDraft())
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(LinearGradient(colors: [Palette.periwinkle, Palette.violet], startPoint: .top, endPoint: .bottom)))
                .shadow(color: Palette.violet.opacity(0.35), radius: 4, y: 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(tr("Neuer Termin (⌥⌘N)", "New Event (⌥⌘N)"))
        .disabled(view.usableAccounts.isEmpty)
        .accessibilityIdentifier("calendar.new")
    }

    @ViewBuilder
    private var search: some View {
        if showsSearch || view.isSearching {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField(tr("Termine suchen", "Search events"), text: $view.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .frame(width: 140)
                    .focused($searchFocused)
                    .onExitCommand { closeSearch() }
                    .accessibilityIdentifier("calendar.search")
                Button(action: closeSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(tr("Suche beenden", "Close Search"))
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
            .task { searchFocused = true }
        } else {
            GlassCircleButton(systemImage: "magnifyingglass", help: tr("Termine suchen (⌘F)", "Search Events (⌘F)")) {
                showsSearch = true
            }
            .keyboardShortcut("f")
            .accessibilityIdentifier("calendar.searchButton")
        }
    }

    private func closeSearch() {
        view.searchText = ""
        showsSearch = false
    }
}

// MARK: - Day and week

private struct CalendarWeekView: View {
    @Environment(AppModel.self) private var model
    @Bindable var view: CalendarViewState

    /// The event being dragged to a new time, with the current drag distance.
    @State private var dragging: (id: String, translation: CGSize)?

    private let hourHeight: CGFloat = 52
    private let gutter: CGFloat = 62
    private let trailing: CGFloat = 10
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            dayHeader
            allDayRow
            timeline
        }
    }

    // MARK: Day header

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: gutter, height: 1)
            ForEach(view.visibleDays, id: \.self) { day in
                dayLabel(day)
            }
        }
        .padding(.trailing, trailing)
        .frame(height: 46)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private func dayLabel(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        return Button {
            view.select(day: day)
            view.mode = .day
        } label: {
            HStack(spacing: 5) {
                Text(day.formatted(.dateTime.weekday(view.mode == .day ? .wide : .abbreviated)))
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                if let location = view.workingLocation(on: day) {
                    Text(location)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(isToday ? Color.accentColor.opacity(0.85) : Color.secondary)
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background {
                if isToday { Capsule().fill(Color.accentColor.opacity(0.14)) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tr("Diesen Tag anzeigen", "Show this day"))
    }

    // MARK: All-day events

    /// An all-day event across one or more of the visible days.
    private struct Span: Identifiable {
        let entry: CalendarEntry
        let first: Int
        let last: Int
        var row = 0
        var id: String { entry.id }
    }

    private var spans: [Span] {
        let days = view.visibleDays
        var seen = Set<String>()
        var spans: [Span] = []
        for (index, day) in days.enumerated() {
            for entry in view.entries(on: day) where entry.event.isAllDay && !seen.contains(entry.id) {
                seen.insert(entry.id)
                let last = days.lastIndex { other in
                    let end = calendar.date(byAdding: .day, value: 1, to: other) ?? other
                    return entry.event.overlaps(from: other, to: end)
                } ?? index
                spans.append(Span(entry: entry, first: index, last: max(last, index)))
            }
        }
        // Longer events on top, then stack into the first free row.
        spans.sort { $0.first == $1.first ? ($0.last - $0.first) > ($1.last - $1.first) : $0.first < $1.first }
        var rowEnds: [Int] = []
        for index in spans.indices {
            if let free = rowEnds.firstIndex(where: { $0 < spans[index].first }) {
                spans[index].row = free
                rowEnds[free] = spans[index].last
            } else {
                spans[index].row = rowEnds.count
                rowEnds.append(spans[index].last)
            }
        }
        return spans
    }

    private var allDayRow: some View {
        let spans = self.spans
        let rows = (spans.map(\.row).max() ?? -1) + 1
        let rowHeight: CGFloat = 25
        let columns = CGFloat(max(view.visibleDays.count, 1))
        return HStack(alignment: .top, spacing: 0) {
            Text(tr("Ganztägig", "All-day"))
                .font(.system(size: 9.5, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: gutter - 8, alignment: .leading)
                .padding(.leading, 12)
                .padding(.top, 9)
                .frame(width: gutter, alignment: .leading)
            GeometryReader { proxy in
                let width = proxy.size.width / columns
                ZStack(alignment: .topLeading) {
                    ForEach(spans) { span in
                        AllDayBar(entry: span.entry, isSelected: view.selectedEventID == span.entry.id) {
                            view.selectedEventID = span.entry.id
                        }
                        .frame(width: max(width * CGFloat(span.last - span.first + 1) - 4, 10), height: rowHeight - 3)
                        .popover(isPresented: popoverBinding(for: span.entry), arrowEdge: .bottom) {
                            EventDetailView(event: span.entry.event, store: span.entry.store, account: span.entry.account)
                        }
                        .contextMenu { eventMenu(span.entry) }
                        .padding(.leading, width * CGFloat(span.first) + 2)
                        .padding(.top, CGFloat(span.row) * rowHeight + 4)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: max(CGFloat(rows) * rowHeight + 6, 30))
        }
        .padding(.trailing, trailing)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    // MARK: Timeline

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
                    .padding(.trailing, trailing)
                    nowLine
                }
                .frame(height: hourHeight * 24)
                .padding(.vertical, 8)
            }
            .onAppear { scrollToStart(proxy) }
            .onChange(of: view.selectedDay) { scrollToStart(proxy) }
            .onChange(of: view.revealRequest) { scrollToStart(proxy) }
        }
    }

    private func scrollToStart(_ proxy: ScrollViewProxy) {
        // An event chosen elsewhere (sidebar, email) comes into view.
        if let selected = view.entry(id: view.selectedEventID), !selected.event.isAllDay, let start = selected.event.startDate,
           view.visibleDays.contains(where: { calendar.isDate($0, inSameDayAs: start) }) {
            proxy.scrollTo("hour-\(min(max(calendar.component(.hour, from: start) - 1, 0), 18))", anchor: .top)
            return
        }
        let firstEvent = view.visibleDays
            .flatMap { view.entries(on: $0).filter { !$0.event.isAllDay } }
            .compactMap(\.event.startDate)
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
                HStack(alignment: .top, spacing: 8) {
                    Text(hourLabel(hour))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .frame(width: gutter - 14, alignment: .trailing)
                        .offset(y: -6)
                        .opacity(hour == 0 ? 0 : 1)
                    Rectangle()
                        .fill(Color.primary.opacity(0.07))
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
                let width = (proxy.size.width - gutter - trailing) / columns
                let minutes = CGFloat(calendar.component(.hour, from: Date()) * 60 + calendar.component(.minute, from: Date()))
                HStack(spacing: 0) {
                    Circle().fill(Color.accentColor).frame(width: 9, height: 9)
                    Rectangle().fill(Color.accentColor).frame(height: 2)
                }
                .frame(width: width + 4)
                .offset(x: gutter + width * CGFloat(index) - 4.5, y: minutes / 60 * hourHeight - 4.5)
            }
            .allowsHitTesting(false)
        }
    }

    private func dayColumn(_ day: Date) -> some View {
        let entries = view.entries(on: day).filter { !$0.event.isAllDay }
        let positioned = TimelineLayout.layout(entries, on: day)
        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.primary.opacity(calendar.isDateInWeekend(day) ? 0.022 : 0))
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 1)
                ForEach(positioned) { item in
                    let laneWidth = (proxy.size.width - 6) / CGFloat(item.lanes)
                    let height = max((item.end - item.start) / 60 * hourHeight - 3, 20)
                    EventBlock(entry: item.entry, isSelected: view.selectedEventID == item.entry.id, height: height) {
                        view.selectedEventID = item.entry.id
                    }
                    .frame(width: max(laneWidth - 3, 10), height: height)
                    .popover(isPresented: popoverBinding(for: item.entry), arrowEdge: .trailing) {
                        EventDetailView(event: item.entry.event, store: item.entry.store, account: item.entry.account)
                    }
                    // Placed with padding (not offset), so the popover points at the block.
                    .padding(.leading, 4 + laneWidth * CGFloat(item.lane))
                    .padding(.top, item.start / 60 * hourHeight + 1.5)
                    .offset(dragOffset(for: item.entry, columnWidth: proxy.size.width))
                    .zIndex(dragging?.id == item.entry.id ? 1 : 0)
                    .highPriorityGesture(dragGesture(for: item.entry, columnWidth: proxy.size.width),
                                         including: item.entry.canEdit ? .all : .subviews)
                    .contextMenu { eventMenu(item.entry) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Moving events

    /// Drag distance snapped to 15 minutes (and whole days in the week view).
    private func snapped(_ translation: CGSize, columnWidth: CGFloat) -> (days: Int, minutes: Int) {
        let days = view.mode == .week ? Int((translation.width / max(columnWidth, 1)).rounded()) : 0
        let minutes = Int((translation.height / hourHeight * 60 / 15).rounded()) * 15
        return (days, minutes)
    }

    private func dragOffset(for entry: CalendarEntry, columnWidth: CGFloat) -> CGSize {
        guard let dragging, dragging.id == entry.id else { return .zero }
        let delta = snapped(dragging.translation, columnWidth: columnWidth)
        return CGSize(width: CGFloat(delta.days) * columnWidth, height: CGFloat(delta.minutes) / 60 * hourHeight)
    }

    private func dragGesture(for entry: CalendarEntry, columnWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                dragging = (entry.id, value.translation)
            }
            .onEnded { value in
                let delta = snapped(value.translation, columnWidth: columnWidth)
                dragging = nil
                let seconds = TimeInterval(delta.days * 86_400 + delta.minutes * 60)
                guard seconds != 0 else { return }
                Task {
                    do {
                        try await entry.store.move(entry.event, by: seconds)
                    } catch {
                        model.present(error, account: entry.account)
                    }
                }
            }
    }

    @ViewBuilder
    private func eventMenu(_ entry: CalendarEntry) -> some View {
        CalendarEventMenu(entry: entry)
    }

    private func popoverBinding(for entry: CalendarEntry) -> Binding<Bool> {
        Binding(
            get: { view.selectedEventID == entry.id },
            set: { if !$0, view.selectedEventID == entry.id { view.selectedEventID = nil } }
        )
    }
}

/// Context menu of an event: edit, open in Google Calendar.
private struct CalendarEventMenu: View {
    @Environment(\.openWindow) private var openWindow
    let entry: CalendarEntry

    var body: some View {
        if entry.canEdit {
            Button(tr("Bearbeiten …", "Edit…")) {
                openWindow(value: EventDraft.editing(entry.event, accountID: entry.account.id))
            }
        }
        if let link = entry.event.htmlLink, let url = URL(string: link) {
            Button(tr("In Google Kalender öffnen", "Open in Google Calendar")) { NSWorkspace.shared.open(url) }
        }
    }
}

// MARK: - Month

/// The month as a grid of days with the first events of each day.
private struct MonthGridView: View {
    @Bindable var view: CalendarViewState
    private let calendar = Calendar.current

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(weekdaySymbols.indices, id: \.self) { index in
                    Text(weekdaySymbols[index])
                        .font(.system(size: 11, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 36)
            .overlay(alignment: .bottom) { Divider().opacity(0.5) }
            GeometryReader { proxy in
                let days = view.monthGrid
                let rows = max(days.count / 7, 1)
                let cellHeight = proxy.size.height / CGFloat(rows)
                VStack(spacing: 0) {
                    ForEach(0..<rows, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { column in
                                let index = row * 7 + column
                                if index < days.count {
                                    cell(days[index], height: cellHeight, width: proxy.size.width / 7)
                                        .frame(width: proxy.size.width / 7, height: cellHeight)
                                }
                            }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("calendar.month")
    }

    private func cell(_ day: Date, height: CGFloat, width: CGFloat) -> some View {
        let entries = view.entries(on: day)
        let capacity = max(Int((height - 30) / 19), 0)
        let shown = Array(entries.prefix(entries.count > capacity ? max(capacity - 1, 0) : capacity))
        let isToday = calendar.isDateInToday(day)
        let isSelected = calendar.isDate(day, inSameDayAs: view.selectedDay)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Spacer()
                Text("\(calendar.component(.day, from: day))")
                    .font(.system(size: 12, weight: isToday ? .bold : .medium))
                    .foregroundStyle(isToday ? Color.white : view.isInDisplayedMonth(day) ? Color.primary : Color.secondary.opacity(0.6))
                    .frame(minWidth: 22, minHeight: 22)
                    .background {
                        if isToday { Circle().fill(Color.accentColor) }
                    }
            }
            ForEach(shown) { entry in
                Button {
                    view.select(day: day)
                    view.selectedEventID = entry.id
                } label: {
                    MonthEventLabel(entry: entry, showsTime: width >= 130)
                }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(
                    get: { view.selectedEventID == entry.id && calendar.isDate(day, inSameDayAs: view.selectedDay) },
                    set: { if !$0, view.selectedEventID == entry.id { view.selectedEventID = nil } }
                ), arrowEdge: .trailing) {
                    EventDetailView(event: entry.event, store: entry.store, account: entry.account)
                }
                .contextMenu { CalendarEventMenu(entry: entry) }
                .accessibilityIdentifier("month.event.\(entry.event.id)")
            }
            if entries.count > shown.count {
                Text(tr("+ \(entries.count - shown.count) weitere", "+ \(entries.count - shown.count) more"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isSelected ? Color.accentColor.opacity(0.07) : view.isInDisplayedMonth(day) ? Color.clear : Color.primary.opacity(0.025))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1)
        }
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.primary.opacity(0.07)).frame(width: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            view.select(day: day)
            view.mode = .day
        }
        .onTapGesture {
            view.select(day: day)
        }
        .accessibilityIdentifier("month.day.\(CalendarDates.dayString(day))")
    }
}

private struct MonthEventLabel: View {
    let entry: CalendarEntry
    let showsTime: Bool

    var body: some View {
        HStack(spacing: 4) {
            if entry.event.isAllDay {
                Text(CalendarFormat.title(entry.event))
                    .font(.system(size: 10.5, weight: .semibold))
                    .lineLimit(1)
                    .padding(.leading, 5)
                    .frame(maxWidth: .infinity, minHeight: 17, alignment: .leading)
                    .background(entry.color.opacity(0.18))
                    .overlay(alignment: .leading) { Rectangle().fill(entry.color).frame(width: 2.5) }
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Circle().fill(entry.color).frame(width: 6, height: 6)
                // Times only where there is room; narrow cells show the title.
                if showsTime {
                    Text(entry.event.startDate?.formatted(date: .omitted, time: .shortened) ?? "")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(CalendarFormat.title(entry.event))
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                    .strikethrough(entry.event.myResponse == .declined)
                Spacer(minLength: 0)
            }
        }
        .frame(height: 17)
        .contentShape(Rectangle())
    }
}

// MARK: - Agenda and search results

/// Days as a list, the date on the left and the events on the right.
private struct AgendaList: View {
    @Bindable var view: CalendarViewState
    let days: [Date]
    let showsEmptyDays: Bool
    private let calendar = Calendar.current

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(days, id: \.self) { day in
                    let entries = view.entries(on: day)
                    if showsEmptyDays || !entries.isEmpty {
                        HStack(alignment: .top, spacing: 18) {
                            dateColumn(day)
                            VStack(alignment: .leading, spacing: 4) {
                                if entries.isEmpty {
                                    Text(tr("Keine Termine", "No events"))
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(.tertiary)
                                        .padding(.vertical, 8)
                                }
                                ForEach(entries) { entry in
                                    AgendaRow(entry: entry, day: day, isSelected: view.selectedEventID == entry.id,
                                              showsAccount: view.accounts.count > 1) {
                                        view.selectedEventID = entry.id
                                    }
                                    .popover(isPresented: Binding(
                                        get: { view.selectedEventID == entry.id },
                                        set: { if !$0, view.selectedEventID == entry.id { view.selectedEventID = nil } }
                                    ), arrowEdge: .trailing) {
                                        EventDetailView(event: entry.event, store: entry.store, account: entry.account)
                                    }
                                    .contextMenu { CalendarEventMenu(entry: entry) }
                                }
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Divider().opacity(0.4).padding(.leading, 22) }
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .accessibilityIdentifier("calendar.agenda")
    }

    private func dateColumn(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        return VStack(spacing: 2) {
            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                .font(.system(size: 10.5, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isToday ? Color.white : Color.primary)
                .frame(width: 40, height: 40)
                .background {
                    if isToday { Circle().fill(Color.accentColor) }
                }
            Text(day.formatted(.dateTime.month(.abbreviated)))
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .frame(width: 52)
    }
}

private struct AgendaRow: View {
    let entry: CalendarEntry
    let day: Date
    let isSelected: Bool
    let showsAccount: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(entry.color)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(CalendarFormat.title(entry.event))
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)
                            .strikethrough(entry.event.myResponse == .declined)
                        if let response = entry.event.myResponse, response != .accepted {
                            RSVPBadge(status: response)
                        }
                    }
                    HStack(spacing: 10) {
                        Text(CalendarFormat.timeRange(entry.event, on: day))
                            .font(.system(size: 12).monospacedDigit())
                        if let location = entry.event.location, !location.isEmpty {
                            Label(location, systemImage: "mappin.and.ellipse")
                                .font(.system(size: 11.5))
                                .lineLimit(1)
                        }
                        if showsAccount {
                            Text(entry.account.email)
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if entry.event.hangoutLink != nil {
                    Image(systemName: "video")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(entry.color.opacity(isSelected ? 0.2 : isHovering ? 0.12 : 0.07))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityIdentifier("agenda.\(entry.event.id)")
    }
}

// MARK: - Layout

/// Places overlapping events side by side.
enum TimelineLayout {
    struct Item: Identifiable {
        let entry: CalendarEntry
        /// Minutes since midnight, clipped to the day.
        let start: CGFloat
        let end: CGFloat
        var lane = 0
        var lanes = 1
        var id: String { entry.id }
    }

    static func layout(_ entries: [CalendarEntry], on day: Date) -> [Item] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        var items: [Item] = entries.compactMap { entry in
            guard let start = entry.event.startDate, let end = entry.event.endDate else { return nil }
            let from = max(0, CGFloat(start.timeIntervalSince(dayStart) / 60))
            let to = min(24 * 60, CGFloat(end.timeIntervalSince(dayStart) / 60))
            guard to > 0, from < 24 * 60 else { return nil }
            return Item(entry: entry, start: from, end: max(to, from + 15))
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

// MARK: - Event blocks

/// An event in the timeline: a coloured bar on the left, title and time on a light tint.
/// Unanswered invitations get a dashed outline, out-of-office time is striped.
private struct EventBlock: View {
    let entry: CalendarEntry
    let isSelected: Bool
    let height: CGFloat
    let action: () -> Void

    private var event: CalendarEvent { entry.event }
    private var color: Color { entry.color }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 7, style: .continuous) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                if !entry.isAwaitingAnswer {
                    Rectangle().fill(color).frame(width: 3)
                }
                content
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { fill }
            .clipShape(shape)
            .overlay { border }
            .opacity(event.myResponse == .declined ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("event.\(event.id)")
    }

    @ViewBuilder
    private var content: some View {
        let title = Text(CalendarFormat.title(event))
            .font(.system(size: 11.5, weight: .semibold))
            .strikethrough(event.myResponse == .declined)
        if height < 34 {
            HStack(spacing: 5) {
                title.lineLimit(1)
                if let start = event.startDate {
                    Text(start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(-1)
                }
            }
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if event.isFocusTime {
                        Image(systemName: "scope")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    title.lineLimit(height >= 60 ? 2 : 1)
                }
                Text(CalendarFormat.shortTimeRange(event))
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if height >= 74, let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
        }
    }

    @ViewBuilder
    private var fill: some View {
        if entry.isAwaitingAnswer {
            Theme.cardFill.opacity(0.9)
        } else if event.isOutOfOffice {
            ZStack {
                color.opacity(0.12)
                Stripes().stroke(color.opacity(0.35), lineWidth: 3)
            }
        } else {
            color.opacity(isSelected ? 0.32 : 0.16)
        }
    }

    @ViewBuilder
    private var border: some View {
        if entry.isAwaitingAnswer {
            shape.strokeBorder(color.opacity(isSelected ? 1 : 0.75), style: StrokeStyle(lineWidth: isSelected ? 1.8 : 1.3, dash: [4, 3]))
        } else if isSelected {
            shape.strokeBorder(color.opacity(0.9), lineWidth: 1.5)
        }
    }
}

/// An all-day event, across the days it lasts.
private struct AllDayBar: View {
    let entry: CalendarEntry
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Rectangle().fill(entry.color).frame(width: 3)
                Text(CalendarFormat.title(entry.event))
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(entry.color.opacity(isSelected ? 0.34 : 0.18))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("event.\(entry.event.id)")
    }
}

/// Diagonal stripes, for out-of-office time.
private struct Stripes: Shape {
    var spacing: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

// MARK: - Event details

struct EventDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
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

            HStack(spacing: 12) {
                if store.canEdit(shown) {
                    Button {
                        openWindow(value: EventDraft.editing(shown, accountID: account.id))
                    } label: {
                        Label(tr("Bearbeiten …", "Edit…"), systemImage: "pencil")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("event.edit")
                }
                if let link = shown.htmlLink, let url = URL(string: link) {
                    Link(destination: url) {
                        Label(tr("In Google Kalender öffnen", "Open in Google Calendar"), systemImage: "arrow.up.right.square")
                            .font(.system(size: 12))
                    }
                }
            }
        }
        .font(.system(size: 12.5))
        .padding(16)
        .frame(width: 380, alignment: .leading)
        .accessibilityElement(children: .contain)
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

    /// "10:00–11:30", for event blocks.
    static func shortTimeRange(_ event: CalendarEvent) -> String {
        guard let start = event.startDate, let end = event.endDate else { return "" }
        return "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
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
