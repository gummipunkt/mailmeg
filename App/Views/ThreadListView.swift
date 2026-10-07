import MailmegKit
import SwiftUI

struct ThreadListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Bindable var mailbox: MailboxModel

    var body: some View {
        List(selection: Binding(get: { model.selectedThreadIDs }, set: { model.setThreadSelection($0) })) {
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
                .onAppear { mailbox.loadMoreIfNeeded(after: thread) }
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
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .overlay { emptyState }
        .onChange(of: mailbox.searchText) { _, newValue in
            if newValue.isEmpty, !mailbox.activeQuery.isEmpty {
                mailbox.submitSearch()
            }
        }
        .navigationTitle(mailbox.title)
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.refreshAll() }
                } label: {
                    Label(tr("Aktualisieren", "Refresh"), systemImage: "arrow.clockwise")
                }
                .help(tr("Neue E-Mails abrufen (⇧⌘N)", "Get New Mail (⇧⌘N)"))
            }
        }
        .glassBackground(.list)
    }

    private func openDraft(_ thread: ThreadSummary) {
        Task {
            if let draft = await model.openDraft(threadID: thread.id) {
                openWindow(value: draft)
            }
        }
    }

    /// Airmail-style header: round glass buttons around a centred title, search below.
    private var header: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                GlassCircleMenu(
                    systemImage: mailbox.unreadOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease",
                    help: tr("Filter", "Filter")
                ) {
                    Picker("Filter", selection: Binding(get: { mailbox.unreadOnly }, set: { mailbox.setUnreadOnly($0) })) {
                        Label(tr("Alle E-Mails", "All Mail"), systemImage: "tray").tag(false)
                        Label(tr("Nur ungelesene", "Unread Only"), systemImage: "envelope.badge").tag(true)
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button(tr("Alle auswählen", "Select All")) { model.selectAllThreads() }
                        .disabled(mailbox.threads.isEmpty)
                }
                .accessibilityIdentifier("mailbox.filter")

                Spacer(minLength: 4)
                VStack(spacing: 1) {
                    Text(mailbox.title)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                        .accessibilityIdentifier("mailbox.title")
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)

                GlassCircleButton(systemImage: "square.and.pencil", help: tr("Neue E-Mail (⌘N)", "New Message (⌘N)")) {
                    openWindow(value: model.newDraft())
                }
                .accessibilityIdentifier("compose")
            }
            SearchField(text: $mailbox.searchText) { mailbox.submitSearch() }
            if !mailbox.activeQuery.isEmpty || model.isMultipleSelection {
                selectionBar
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frostedBar(tint: Theme.listBackground)
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

/// Capsule search field in the list header (Gmail search syntax works, e.g. `from:anna`).
struct SearchField: View {
    @Binding var text: String
    var prompt = tr("Suchen – z. B. from:anna has:attachment", "Search – e.g. from:anna has:attachment")
    var identifier = "mailbox.search"
    let onSubmit: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
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
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .overlay(Capsule().strokeBorder(isFocused ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.22), lineWidth: isFocused ? 1.5 : 0.8))
    }
}

struct ThreadRow: View {
    let thread: ThreadSummary
    let labels: [GmailLabel]
    let isTrash: Bool
    var showsImportant = false
    let onAction: (ThreadAction) -> Void
    @AppStorage(AppSettings.showAvatarsKey) private var showAvatars = false
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showAvatars {
                AvatarView(name: thread.correspondents.first ?? thread.participants.first ?? "?", size: 34)
            }
            // Unread marker in its own narrow gutter, like Airmail.
            Circle()
                .fill(thread.isUnread ? Color.accentColor : Color.clear)
                .frame(width: 8, height: 8)
                .padding(.top, 6)
                .padding(.leading, showAvatars ? -6 : 0)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(senderLine)
                        .font(.system(size: 13.5, weight: thread.isUnread ? .bold : .semibold))
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
                        .font(.system(size: 12.5, weight: thread.isUnread ? .semibold : .medium))
                        .foregroundStyle(.primary.opacity(0.9))
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
        .padding(.vertical, 9)
        .padding(.trailing, 2)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
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
        .background(.regularMaterial, in: Capsule())
    }
}
