import AppKit
import MailmegKit
import SwiftUI

struct ThreadListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Bindable var mailbox: MailboxModel
    @AppStorage(AppSettings.swipeLeftKey) private var swipeLeft = AppSettings.SwipeAction.archive.rawValue
    @AppStorage(AppSettings.swipeRightKey) private var swipeRight = AppSettings.SwipeAction.trash.rawValue
    @State private var swiper = RowSwiper()

    var body: some View {
        VStack(spacing: 0) {
            header
            list
                .overlay { emptyState }
        }
        // The list is a frosted sheet floating on the backdrop.
        .floatingPanel()
        .padding(.horizontal, 8)
        .padding(.top, 2)
        .padding(.bottom, 10)
        .onChange(of: mailbox.searchText) { _, newValue in
            if newValue.isEmpty, !mailbox.activeQuery.isEmpty {
                mailbox.submitSearch()
            }
        }
        .navigationTitle(mailbox.title)
        .toolbar { toolbar }
        .glassBackground(.list)
    }

    /// The system toolbar above the list: fetch and filter on the left, a new message on the right.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                Task { await model.refreshAll() }
            } label: {
                Label(tr("Abrufen", "Get Mail"), systemImage: "arrow.clockwise")
            }
            .help(tr("Neue E-Mails abrufen (⇧⌘N)", "Get New Mail (⇧⌘N)"))
            .accessibilityIdentifier("mailbox.refresh")

            Menu {
                Picker("Filter", selection: Binding(get: { mailbox.unreadOnly }, set: { mailbox.setUnreadOnly($0) })) {
                    Label(tr("Alle E-Mails", "All Mail"), systemImage: "tray").tag(false)
                    Label(tr("Nur ungelesene", "Unread Only"), systemImage: "envelope.badge").tag(true)
                }
                .pickerStyle(.inline)
                Divider()
                Button(tr("Alle auswählen", "Select All")) { model.selectAllThreads() }
                    .disabled(mailbox.threads.isEmpty)
            } label: {
                Label(tr("Filter", "Filter"), systemImage: mailbox.unreadOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .menuIndicator(.hidden)
            .help(mailbox.unreadOnly ? tr("Filter: nur ungelesene", "Filter: unread only") : tr("Filter", "Filter"))
            .accessibilityIdentifier("mailbox.filter")
        }
        ToolbarFlexibleGap()
        ToolbarItem {
            Button {
                openWindow(value: model.newDraft())
            } label: {
                Label(tr("Neue E-Mail", "New Message"), systemImage: "square.and.pencil")
            }
            .buttonStyle(.borderedProminent)
            .help(tr("Neue E-Mail (⌘N)", "New Message (⌘N)"))
            .accessibilityIdentifier("compose")
        }
    }

    private var list: some View {
        let withoutSeparator = separatorlessIDs
        return List(selection: Binding(get: { model.selectedThreadIDs }, set: { model.setThreadSelection($0) })) {
            ForEach(mailbox.threads) { thread in
                ThreadRow(
                    thread: thread,
                    labels: mailbox.account.userLabels(in: thread.labelIDs).filter { $0.id != mailbox.labelID },
                    isTrash: mailbox.labelID == SystemLabel.trash,
                    showsImportant: mailbox.labelID != SystemLabel.important && thread.labelIDs.contains(SystemLabel.important),
                    onAction: { model.perform($0, threadID: thread.id) }
                )
                .tag(thread.id)
                .accessibilityIdentifier("thread.\(thread.id)")
                .listRowSeparator(.hidden)
                // A soft tint marks the selection instead of the table's solid highlight.
                // A short line between two conversations, not across the whole width.
                .overlay(alignment: .bottom) {
                    if !withoutSeparator.contains(thread.id) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.13))
                            .frame(height: 1)
                            .padding(.horizontal, 44)
                            .allowsHitTesting(false)
                    }
                }
                // Swiping with two fingers moves the row; what appears behind it is the action.
                .offset(x: swiper.threadID == thread.id ? swiper.offset : 0)
                .onHover { inside in
                    if inside {
                        swiper.hoveredID = thread.id
                    } else if swiper.hoveredID == thread.id {
                        swiper.hoveredID = nil
                    }
                }
                .listRowBackground(rowBackground(for: thread))
                .onAppear { mailbox.loadMoreIfNeeded(after: thread) }
                // Drag onto a mailbox or label in the sidebar; a selected row takes the
                // whole selection along.
                .draggable(dragPayload(for: thread).text) {
                    DragPreview(count: dragPayload(for: thread).threadIDs.count, subject: thread.subject)
                }
            }
            if mailbox.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        // Right-click menu, and double-click (or Return) on a draft to keep writing it.
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count > 1 {
                bulkContextMenu(for: ids)
            } else if let id = ids.first, let thread = mailbox.thread(id: id) {
                contextMenu(for: thread)
            }
        } primaryAction: { ids in
            guard ids.count == 1, let id = ids.first, let thread = mailbox.thread(id: id),
                  thread.labelIDs.contains(SystemLabel.draft) else { return }
            openDraft(thread)
        }
        // The Delete key moves the selection to the trash (⌘Z brings it back).
        .onDeleteCommand {
            if model.hasThreadSelection, mailbox.labelID != SystemLabel.trash {
                model.perform(.trash)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .onAppear {
            // The handlers ask for the mailbox that is open at that moment.
            swiper.canSwipe = { [model] id, toLeft in
                Self.swipeItem(toLeft: toLeft, threadID: id, mailbox: model.mailbox) != nil
            }
            swiper.onCommit = { [model] id, toLeft in
                if let item = Self.swipeItem(toLeft: toLeft, threadID: id, mailbox: model.mailbox) {
                    model.perform(item.action, threadID: id)
                }
            }
            swiper.dragPayload = { [model] id in
                guard let mailbox = model.mailbox else { return nil }
                return Self.dragPayload(for: id, in: mailbox, selected: model.selectedThreadIDs).text
            }
            swiper.start()
        }
        .onDisappear { swiper.stop() }
        // Where the list lies in the window, for swipes with the mouse.
        .background {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear { swiper.listRange = frame.minX...frame.maxX }
                    .onChange(of: frame) { _, newFrame in swiper.listRange = newFrame.minX...newFrame.maxX }
            }
        }
    }

    /// The selection tint and, while a row is swiped aside, the action behind it.
    private func rowBackground(for thread: ThreadSummary) -> some View {
        let offset = swiper.threadID == thread.id ? swiper.offset : 0
        let item = offset == 0 ? nil : Self.swipeItem(toLeft: offset < 0, threadID: thread.id, mailbox: mailbox)
        return ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(model.selectedThreadIDs.contains(thread.id) ? Theme.selection : Color.clear)
            if let item {
                SwipeReveal(item: item, offset: offset)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
    }

    /// Conversations that get no line below them: selected ones, the one above a selected
    /// one (the selection has its own outline) and the last.
    private var separatorlessIDs: Set<String> {
        let selected = model.selectedThreadIDs
        let threads = mailbox.threads
        var hidden = selected
        for (index, thread) in threads.enumerated() where index > 0 && selected.contains(thread.id) {
            hidden.insert(threads[index - 1].id)
        }
        if let last = threads.last { hidden.insert(last.id) }
        return hidden
    }

    // MARK: Swiping

    /// What swiping a conversation to the left or right does in this mailbox (as set in
    /// Settings), or nil if nothing applies.
    static func swipeItem(toLeft: Bool, threadID: String, mailbox: MailboxModel?) -> SwipeItem? {
        guard let mailbox, let thread = mailbox.thread(id: threadID) else { return nil }
        let key = toLeft ? AppSettings.swipeLeftKey : AppSettings.swipeRightKey
        let fallback: AppSettings.SwipeAction = toLeft ? .archive : .trash
        let swipe = UserDefaults.standard.string(forKey: key).flatMap(AppSettings.SwipeAction.init(rawValue:)) ?? fallback
        let inTrash = mailbox.labelID == SystemLabel.trash
        let inSpam = mailbox.labelID == SystemLabel.spam
        switch swipe {
        case .none:
            return nil
        case .archive:
            if inTrash {
                return SwipeItem(action: .untrash, title: tr("Wiederherstellen", "Restore"), systemImage: "arrow.uturn.backward", color: Color(hex: "#2BB5A3"))
            }
            if inSpam {
                return SwipeItem(action: .notSpam, title: tr("Kein Spam", "Not Spam"), systemImage: "checkmark.shield.fill", color: Color(hex: "#2BB5A3"))
            }
            guard thread.labelIDs.contains(SystemLabel.inbox) else { return nil }
            return SwipeItem(action: .archive, title: tr("Archivieren", "Archive"), systemImage: "archivebox.fill", color: Color(hex: "#2BB5A3"))
        case .trash:
            return inTrash ? nil : SwipeItem(action: .trash, title: tr("Löschen", "Delete"), systemImage: "trash.fill", color: Color(hex: "#E5534B"))
        case .toggleRead:
            return thread.isUnread
                ? SwipeItem(action: .markRead, title: tr("Gelesen", "Read"), systemImage: "envelope.open.fill", color: Color(hex: "#3B9BF5"))
                : SwipeItem(action: .markUnread, title: tr("Ungelesen", "Unread"), systemImage: "envelope.badge.fill", color: Color(hex: "#3B9BF5"))
        case .toggleStar:
            return thread.isStarred
                ? SwipeItem(action: .unstar, title: tr("Entmarkieren", "Unstar"), systemImage: "star.slash.fill", color: Color(hex: "#F2A900"))
                : SwipeItem(action: .star, title: tr("Markieren", "Star"), systemImage: "star.fill", color: Color(hex: "#F2A900"))
        case .spam:
            return inSpam || inTrash ? nil : SwipeItem(action: .reportSpam, title: "Spam", systemImage: "xmark.octagon.fill", color: Color(hex: "#7B839A"))
        }
    }

    private func dragPayload(for thread: ThreadSummary) -> ThreadDrag {
        Self.dragPayload(for: thread.id, in: mailbox, selected: model.selectedThreadIDs)
    }

    /// What a drag of a row carries: the row, or the whole selection if the row is part of it.
    static func dragPayload(for threadID: String, in mailbox: MailboxModel, selected: Set<String>) -> ThreadDrag {
        let ids = selected.contains(threadID) && selected.count > 1
            ? mailbox.threads.map(\.id).filter(selected.contains)
            : [threadID]
        return ThreadDrag(accountID: mailbox.account.id, threadIDs: ids)
    }

    private func openDraft(_ thread: ThreadSummary) {
        Task {
            if let draft = await model.openDraft(threadID: thread.id) {
                openWindow(value: draft)
            }
        }
    }

    /// Big title with the counts, search below.
    private var header: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mailbox.title)
                        .font(.system(size: 22, weight: .bold))
                        .tracking(-0.3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityIdentifier("mailbox.title")
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
            }
            SearchField(text: $mailbox.searchText, focusRequest: model.searchRequest) { mailbox.submitSearch() }
            if !mailbox.activeQuery.isEmpty || model.isMultipleSelection {
                selectionBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    /// Result count and selection buttons, shown for searches and when several
    /// conversations are selected.
    private var selectionBar: some View {
        HStack(spacing: 8) {
            Text(selectionSummary)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("list.selectionSummary")
            if model.isSelectingAll {
                ProgressView().controlSize(.mini)
            }
            Spacer(minLength: 4)
            if model.isMultipleSelection {
                if mailbox.nextPageToken != nil, model.selectedThreadIDs.count >= mailbox.threads.count {
                    selectionButton(tr("Alle Ergebnisse", "All Results"), identifier: "list.selectAllResults") { model.selectAllThreads() }
                }
                selectionButton(tr("Auswahl aufheben", "Deselect"), identifier: "list.clearSelection") { model.clearThreadSelection() }
            } else if !mailbox.threads.isEmpty {
                selectionButton(tr("Alle auswählen", "Select All"), identifier: "list.selectAll") { model.selectAllThreads() }
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 22)
    }

    private func selectionButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(model.isSelectingAll)
        .accessibilityIdentifier(identifier)
    }

    private var selectionSummary: String {
        let selected = model.selectedThreadIDs.count
        if selected > 1 {
            return tr("\(selected) ausgewählt", "\(selected) selected")
        }
        let count = mailbox.threads.count
        let total = "\(count)\(mailbox.nextPageToken != nil ? "+" : "")"
        return count == 1 ? tr("1 Ergebnis", "1 result") : tr("\(total) Ergebnisse", "\(total) results")
    }

    private var subtitle: String {
        if mailbox.isLoading && !mailbox.hasLoaded { return tr("Wird geladen …", "Loading…") }
        let unread = mailbox.unreadCount
        let count = mailbox.threads.count
        let total = "\(count)\(mailbox.nextPageToken != nil ? "+" : "")"
        if unread > 0 { return tr("\(unread) ungelesen · \(total) gesamt", "\(unread) unread · \(total) total") }
        return count == 1 ? tr("1 Konversation", "1 conversation") : tr("\(total) Konversationen", "\(total) conversations")
    }

    @ViewBuilder
    private var emptyState: some View {
        if mailbox.isLoading && mailbox.threads.isEmpty {
            ProgressView()
        } else if mailbox.hasLoaded && mailbox.threads.isEmpty {
            if !mailbox.activeQuery.isEmpty {
                ContentUnavailableView.search(text: mailbox.activeQuery)
            } else if mailbox.unreadOnly {
                ContentUnavailableView(tr("Alles gelesen", "All Read"), systemImage: "checkmark.circle", description: Text(tr("Hier gibt es keine ungelesenen E-Mails.", "There’s no unread email here.")))
            } else {
                ContentUnavailableView(tr("Keine E-Mails", "No Email"), systemImage: "tray", description: Text(tr("Dieser Ordner ist leer.", "This folder is empty.")))
            }
        }
    }

    /// Right-click on several selected conversations.
    @ViewBuilder
    private func bulkContextMenu(for ids: Set<String>) -> some View {
        let threads = mailbox.threads.filter { ids.contains($0.id) }
        Button(tr("\(threads.count) als gelesen markieren", "Mark \(threads.count) as Read")) { bulk(.markRead, ids) }
        Button(tr("\(threads.count) als ungelesen markieren", "Mark \(threads.count) as Unread")) { bulk(.markUnread, ids) }
        Button(threads.allSatisfy(\.isStarred) ? tr("Markierungen entfernen", "Remove Stars") : tr("Alle markieren", "Star All")) {
            bulk(threads.allSatisfy(\.isStarred) ? .unstar : .star, ids)
        }
        Divider()
        if mailbox.labelID == SystemLabel.trash {
            Button(tr("Wiederherstellen", "Restore")) { bulk(.untrash, ids) }
        } else if mailbox.labelID == SystemLabel.spam {
            Button(tr("Kein Spam", "Not Spam")) { bulk(.notSpam, ids) }
        } else {
            Button(tr("Archivieren", "Archive")) { bulk(.archive, ids) }
            Button(tr("Als Spam melden", "Report Spam")) { bulk(.reportSpam, ids) }
            Button(tr("In den Papierkorb", "Move to Trash")) { bulk(.trash, ids) }
        }
    }

    private func bulk(_ action: ThreadAction, _ ids: Set<String>) {
        model.setThreadSelection(ids)
        model.performOnSelection(action)
    }

    @ViewBuilder
    private func contextMenu(for thread: ThreadSummary) -> some View {
        if thread.labelIDs.contains(SystemLabel.draft) {
            Button(tr("Entwurf bearbeiten", "Edit Draft")) { openDraft(thread) }
            Divider()
        }
        Button(thread.isUnread ? tr("Als gelesen markieren", "Mark as Read") : tr("Als ungelesen markieren", "Mark as Unread")) {
            model.perform(thread.isUnread ? .markRead : .markUnread, threadID: thread.id)
        }
        Button(thread.isStarred ? tr("Markierung entfernen", "Remove Star") : tr("Markieren", "Star")) {
            model.perform(thread.isStarred ? .unstar : .star, threadID: thread.id)
        }
        Divider()
        if mailbox.labelID == SystemLabel.trash {
            Button(tr("Wiederherstellen", "Restore")) { model.perform(.untrash, threadID: thread.id) }
        } else if mailbox.labelID == SystemLabel.spam {
            Button(tr("Kein Spam", "Not Spam")) { model.perform(.notSpam, threadID: thread.id) }
        } else {
            if thread.labelIDs.contains(SystemLabel.inbox) {
                Button(tr("Archivieren", "Archive")) { model.perform(.archive, threadID: thread.id) }
            } else {
                Button(tr("In den Posteingang", "Move to Inbox")) { model.perform(.moveToInbox, threadID: thread.id) }
            }
            Button(tr("Als Spam melden", "Report Spam")) { model.perform(.reportSpam, threadID: thread.id) }
            Button(tr("In den Papierkorb", "Move to Trash")) { model.perform(.trash, threadID: thread.id) }
        }
    }
}

// MARK: - Swiping rows

/// One action a swipe can trigger, with the looks of the area behind the row.
struct SwipeItem {
    let action: ThreadAction
    let title: String
    let systemImage: String
    let color: Color
}

/// The coloured area that appears behind a row while it is swiped aside.
private struct SwipeReveal: View {
    let item: SwipeItem
    let offset: CGFloat

    var body: some View {
        let width = abs(offset)
        let isArmed = width >= RowSwiper.threshold
        HStack(spacing: 0) {
            if offset < 0 { Spacer(minLength: 0) }
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(item.color.opacity(isArmed ? 1 : 0.75))
                .overlay(alignment: offset < 0 ? .trailing : .leading) {
                    VStack(spacing: 3) {
                        Image(systemName: item.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(width: 84)
                    .scaleEffect(isArmed ? 1.12 : 0.92)
                    .opacity(min(1, Double(width) / 44))
                    .animation(.spring(duration: 0.2), value: isArmed)
                }
                .frame(width: width)
                .clipped()
            if offset > 0 { Spacer(minLength: 0) }
        }
    }
}

/// Swiping rows of the message list aside:
/// - two fingers on the trackpad (or one on a Magic Mouse): a mostly horizontal gesture moves
///   the row under the pointer, vertical scrolling is left to the list;
/// - the mouse: press on a row and push it left or right. Pushed out of the list towards the
///   sidebar it turns into a drag, so conversations can still be dropped on a label.
/// Letting go beyond the threshold triggers the action, otherwise the row springs back.
@MainActor
@Observable
final class RowSwiper {
    /// How far a row has to be moved for the action to fire on release.
    static let threshold: CGFloat = 96
    private static let limit: CGFloat = 220

    /// The row being moved and how far.
    private(set) var threadID: String?
    private(set) var offset: CGFloat = 0

    /// The row under the pointer; set by the rows.
    @ObservationIgnored var hoveredID: String?
    /// The list's horizontal extent in the window.
    @ObservationIgnored var listRange: ClosedRange<CGFloat>?
    /// Whether a row can be swiped to the left (true) or right (false).
    @ObservationIgnored var canSwipe: ((String, Bool) -> Bool)?
    @ObservationIgnored var onCommit: ((String, Bool) -> Void)?
    /// The text a drag of this row carries (see `ThreadDrag`).
    @ObservationIgnored var dragPayload: ((String) -> String?)?

    private enum Axis { case undecided, vertical, horizontal }
    @ObservationIgnored private var axis = Axis.undecided
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private let dragSource = RowDragSource()

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .leftMouseDown {
                return self.handleMouseDown(event)
            }
            return self.handleScroll(event) ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        axis = .undecided
        threadID = nil
        offset = 0
    }

    // MARK: Moving the row

    private func move(to proposed: CGFloat, id: String) {
        var next = proposed
        if next != 0, canSwipe?(id, next < 0) != true {
            next = 0
        }
        next = min(max(next, -Self.limit), Self.limit)
        let wasArmed = abs(offset) >= Self.threshold
        let isArmed = abs(next) >= Self.threshold
        if isArmed != wasArmed {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        offset = next
    }

    private func finish(id: String, commits: Bool) {
        let fires = commits && abs(offset) >= Self.threshold
        let toLeft = offset < 0
        withAnimation(.spring(duration: 0.28)) {
            offset = 0
        }
        if fires {
            threadID = nil
            onCommit?(id, toLeft)
        }
    }

    // MARK: Trackpad

    /// Returns true if the event belonged to a swipe and must not reach the list.
    private func handleScroll(_ event: NSEvent) -> Bool {
        // Only gestures with phases: trackpad and Magic Mouse. A wheel just scrolls.
        guard event.hasPreciseScrollingDeltas, !event.phase.isEmpty else { return false }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            axis = .undecided
        }
        if axis == .undecided {
            let dx = abs(event.scrollingDeltaX)
            let dy = abs(event.scrollingDeltaY)
            if dx > 0 || dy > 0 {
                if dx > dy * 1.4, let id = hoveredID {
                    axis = .horizontal
                    threadID = id
                    offset = 0
                } else {
                    axis = .vertical
                }
            }
        }
        guard axis == .horizontal, let id = threadID else { return false }

        if event.phase.contains(.changed) || event.phase.contains(.began) {
            // The row follows the fingers, whatever the scroll direction setting.
            let delta = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            move(to: offset + delta, id: id)
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            axis = .undecided
            finish(id: id, commits: event.phase.contains(.ended))
        }
        return true
    }

    // MARK: Mouse

    /// A press on a row: waits for the first few points of movement. Sideways it becomes a
    /// swipe that is tracked here; anything else (a click, a drag up or down) is handed back
    /// to the list untouched.
    private func handleMouseDown(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard let id = hoveredID, let window = event.window, event.clickCount == 1, modifiers.isEmpty,
              let listRange, listRange.contains(event.locationInWindow.x) else { return event }
        let start = event.locationInWindow
        var held: [NSEvent] = []
        var isSwipe = false
        // Not for long: a press that rests is the list's business (it selects the row).
        let deadline = Date().addingTimeInterval(0.35)
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: deadline, inMode: .eventTracking, dequeue: true) {
            held.append(next)
            if next.type == .leftMouseUp { break }
            let dx = next.locationInWindow.x - start.x
            let dy = next.locationInWindow.y - start.y
            if abs(dx) < 5, abs(dy) < 5 { continue }
            isSwipe = abs(dx) > abs(dy) * 2 && canSwipe?(id, dx < 0) == true
            break
        }
        guard isSwipe else {
            // Give the list the events that were looked at, in their order.
            for heldEvent in held.reversed() {
                NSApp.postEvent(heldEvent, atStart: true)
            }
            return event
        }
        trackMouseSwipe(id: id, window: window, startX: start.x)
        return nil
    }

    private func trackMouseSwipe(id: String, window: NSWindow, startX: CGFloat) {
        threadID = id
        offset = 0
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp {
                finish(id: id, commits: true)
                return
            }
            // Out of the list towards the sidebar: this is a drag onto a mailbox or label.
            if let listRange, next.locationInWindow.x < listRange.lowerBound {
                finish(id: id, commits: false)
                beginDrag(id: id, event: next, window: window)
                return
            }
            move(to: next.locationInWindow.x - startX, id: id)
        }
        finish(id: id, commits: false)
    }

    private func beginDrag(id: String, event: NSEvent, window: NSWindow) {
        guard let text = dragPayload?(id), let view = window.contentView else { return }
        let item = NSDraggingItem(pasteboardWriter: text as NSString)
        let image = Self.dragImage
        let point = view.convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            NSRect(x: point.x - image.size.width / 2, y: point.y - image.size.height / 2, width: image.size.width, height: image.size.height),
            contents: image
        )
        view.beginDraggingSession(with: [item], event: event, source: dragSource)
    }

    /// What follows the pointer in such a drag: an envelope on the accent colour.
    private static let dragImage: NSImage = {
        let size = NSSize(width: 44, height: 32)
        return NSImage(size: size, flipped: false) { rect in
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10).fill()
            let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            if let symbol = NSImage(systemSymbolName: "envelope.fill", accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
                symbol.draw(at: NSPoint(x: rect.midX - symbol.size.width / 2, y: rect.midY - symbol.size.height / 2), from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
    }()
}

/// The source of a drag that started as a mouse swipe.
private final class RowDragSource: NSObject, NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        [.copy, .move, .generic]
    }
}

/// What follows the pointer while conversations are dragged.
private struct DragPreview: View {
    let count: Int
    let subject: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: count > 1 ? "envelope.badge.fill" : "envelope.fill")
                .foregroundStyle(.white)
            Text(count > 1
                ? tr("\(count) Konversationen", "\(count) conversations")
                : (subject.isEmpty ? tr("(kein Betreff)", "(no subject)") : subject))
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .frame(maxWidth: 260)
        .background(Capsule().fill(Theme.accentGradient))
    }
}

/// Capsule search field in the list header (Gmail search syntax works, e.g. `from:anna`).
struct SearchField: View {
    @Binding var text: String
    var prompt = tr("Suchen – z. B. from:anna has:attachment", "Search – e.g. from:anna has:attachment")
    var identifier = "mailbox.search"
    /// Changes when the field should take the focus (Edit > Find).
    var focusRequest = 0
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($isFocused)
                .onSubmit(onSubmit)
                .accessibilityIdentifier(identifier)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(tr("Suche löschen", "Clear Search"))
                .accessibilityLabel(tr("Suche löschen", "Clear Search"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Capsule().fill(Theme.tint))
        .overlay(Capsule().strokeBorder(Color.accentColor.opacity(isFocused ? 0.7 : 0), lineWidth: 1.5))
        .onChange(of: focusRequest) { isFocused = true }
    }
}

struct ThreadRow: View {
    let thread: ThreadSummary
    let labels: [GmailLabel]
    let isTrash: Bool
    var showsImportant = false
    let onAction: (ThreadAction) -> Void
    @AppStorage(AppSettings.showAvatarsKey) private var showAvatars = true
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showAvatars {
                // The unread marker sits on the picture.
                AvatarView(name: thread.correspondents.first ?? thread.participants.first ?? "?", email: thread.correspondentAddress, size: 36)
                    .overlay(alignment: .topLeading) {
                        if thread.isUnread {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(Theme.solidCard, lineWidth: 2))
                                .offset(x: -2, y: -2)
                        }
                    }
                    .padding(.top, 1)
            } else {
                // Without pictures the marker gets its own narrow gutter.
                Circle()
                    .fill(thread.isUnread ? Color.accentColor : Color.clear)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(senderLine)
                        .font(.system(size: 13.5, weight: thread.isUnread ? .bold : .medium))
                        .lineLimit(1)
                    if thread.messageCount > 1 {
                        Text("\(thread.messageCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08), in: Capsule())
                    }
                    Spacer(minLength: 6)
                    if isHovering {
                        quickActions
                    } else {
                        trailingInfo
                    }
                }
                .frame(height: 20)

                HStack(spacing: 5) {
                    if thread.labelIDs.contains(SystemLabel.draft) {
                        Text(tr("Entwurf", "Draft"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(thread.subject.isEmpty ? tr("(kein Betreff)", "(no subject)") : thread.subject)
                        .font(.system(size: 12.5, weight: thread.isUnread ? .semibold : .regular))
                        .foregroundStyle(.primary.opacity(thread.isUnread ? 0.95 : 0.82))
                        .lineLimit(1)
                }
                Text(thread.snippet)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if showsImportant || !labels.isEmpty {
                    HStack(spacing: 4) {
                        if showsImportant {
                            ImportantChip()
                        }
                        ForEach(labels.prefix(3)) { LabelChip(label: $0) }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .background(ListHighlightRemover().frame(width: 0, height: 0))
    }

    private var senderLine: String {
        if thread.isOnlyOwnMessages {
            return thread.correspondents.isEmpty ? tr("(kein Empfänger)", "(no recipient)") : tr("An: ", "To: ") + thread.correspondents.joined(separator: ", ")
        }
        return thread.participants.isEmpty ? tr("(unbekannt)", "(unknown)") : thread.participants.joined(separator: ", ")
    }

    private var trailingInfo: some View {
        HStack(spacing: 5) {
            if thread.hasAttachments {
                Image(systemName: "paperclip")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            if thread.isStarred {
                Image(systemName: "star.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.accentColor)
            }
            Text(Formatting.listDate(thread.date))
                .font(.system(size: 11.5, weight: thread.isUnread ? .semibold : .regular))
                .foregroundStyle(thread.isUnread ? Color.accentColor : .secondary)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 0) {
            if isTrash {
                IconButton(systemImage: "arrow.uturn.backward", help: tr("Wiederherstellen", "Restore"), tint: .primary) { onAction(.untrash) }
            } else {
                IconButton(systemImage: "archivebox", help: tr("Archivieren", "Archive"), tint: .primary) { onAction(.archive) }
                IconButton(systemImage: "trash", help: tr("In den Papierkorb", "Move to Trash"), tint: .primary) { onAction(.trash) }
            }
            IconButton(
                systemImage: thread.isUnread ? "envelope.open" : "envelope.badge",
                help: thread.isUnread ? tr("Als gelesen markieren", "Mark as Read") : tr("Als ungelesen markieren", "Mark as Unread"),
                tint: .primary
            ) { onAction(thread.isUnread ? .markRead : .markUnread) }
            IconButton(
                systemImage: thread.isStarred ? "star.fill" : "star",
                help: thread.isStarred ? tr("Markierung entfernen", "Remove Star") : tr("Markieren", "Star"),
                tint: thread.isStarred ? .accentColor : .primary
            ) { onAction(thread.isStarred ? .unstar : .star) }
        }
        .padding(.horizontal, 2)
        .background(Theme.solidCard, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
    }
}
