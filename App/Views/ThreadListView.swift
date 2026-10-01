import MailmegKit
import SwiftUI

struct ThreadListView: View {
    @Environment(AppModel.self) private var model
    @Bindable var mailbox: MailboxModel

    var body: some View {
        List(selection: Binding(get: { model.selectedThreadID }, set: { model.selectThread($0) })) {
            ForEach(mailbox.threads) { thread in
                ThreadRow(
                    thread: thread,
                    labels: mailbox.account.userLabels(in: thread.labelIDs).filter { $0.id != mailbox.labelID },
                    isTrash: mailbox.labelID == SystemLabel.trash,
                    onAction: { model.perform($0, threadID: thread.id) }
                )
                .tag(thread.id)
                .accessibilityIdentifier("thread.\(thread.id)")
                .onAppear { mailbox.loadMoreIfNeeded(after: thread) }
                .contextMenu { contextMenu(for: thread) }
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
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Theme.listBackground)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .overlay { emptyState }
        .searchable(text: $mailbox.searchText, placement: .toolbar, prompt: "Suchen – z. B. from:anna has:attachment")
        .onSubmit(of: .search) { mailbox.submitSearch() }
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
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }
                .help("Neue E-Mails abrufen (⇧⌘N)")
            }
        }
        .themedWindowBackground(Theme.listBackground)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(mailbox.title)
                    .font(.system(size: 20, weight: .bold))
                    .accessibilityIdentifier("mailbox.title")
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Picker("Filter", selection: Binding(get: { mailbox.unreadOnly }, set: { mailbox.setUnreadOnly($0) })) {
                Text("Alle").tag(false)
                Text("Ungelesen").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Theme.listBackground)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var subtitle: String {
        if mailbox.isLoading && !mailbox.hasLoaded { return "Wird geladen …" }
        let unread = mailbox.unreadCount
        let count = mailbox.threads.count
        let total = "\(count)\(mailbox.nextPageToken != nil ? "+" : "")"
        if unread > 0 { return "\(unread) ungelesen · \(total) gesamt" }
        return count == 1 ? "1 Konversation" : "\(total) Konversationen"
    }

    @ViewBuilder
    private var emptyState: some View {
        if mailbox.isLoading && mailbox.threads.isEmpty {
            ProgressView()
        } else if mailbox.hasLoaded && mailbox.threads.isEmpty {
            if !mailbox.activeQuery.isEmpty {
                ContentUnavailableView.search(text: mailbox.activeQuery)
            } else if mailbox.unreadOnly {
                ContentUnavailableView("Alles gelesen", systemImage: "checkmark.circle", description: Text("Hier gibt es keine ungelesenen E-Mails."))
            } else {
                ContentUnavailableView("Keine E-Mails", systemImage: "tray", description: Text("Dieser Ordner ist leer."))
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for thread: ThreadSummary) -> some View {
        Button(thread.isUnread ? "Als gelesen markieren" : "Als ungelesen markieren") {
            model.perform(thread.isUnread ? .markRead : .markUnread, threadID: thread.id)
        }
        Button(thread.isStarred ? "Markierung entfernen" : "Markieren") {
            model.perform(thread.isStarred ? .unstar : .star, threadID: thread.id)
        }
        Divider()
        if mailbox.labelID == SystemLabel.trash {
            Button("Wiederherstellen") { model.perform(.untrash, threadID: thread.id) }
        } else if mailbox.labelID == SystemLabel.spam {
            Button("Kein Spam") { model.perform(.notSpam, threadID: thread.id) }
        } else {
            if thread.labelIDs.contains(SystemLabel.inbox) {
                Button("Archivieren") { model.perform(.archive, threadID: thread.id) }
            } else {
                Button("In den Posteingang") { model.perform(.moveToInbox, threadID: thread.id) }
            }
            Button("Als Spam melden") { model.perform(.reportSpam, threadID: thread.id) }
            Button("In den Papierkorb") { model.perform(.trash, threadID: thread.id) }
        }
    }
}

struct ThreadRow: View {
    let thread: ThreadSummary
    let labels: [GmailLabel]
    let isTrash: Bool
    let onAction: (ThreadAction) -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            AvatarView(name: thread.correspondents.first ?? thread.participants.first ?? "?", size: 36)
                .overlay(alignment: .topLeading) {
                    if thread.isUnread {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(Theme.listBackground, lineWidth: 2))
                            .offset(x: -3, y: -3)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(senderLine)
                        .font(.system(size: 13, weight: thread.isUnread ? .bold : .medium))
                        .lineLimit(1)
                    if thread.messageCount > 1 {
                        Text("\(thread.messageCount)")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.tint, in: Capsule())
                    }
                    Spacer(minLength: 6)
                    if isHovering {
                        quickActions
                    } else {
                        trailingInfo
                    }
                }
                .frame(height: 20)

                Text(thread.subject.isEmpty ? "(kein Betreff)" : thread.subject)
                    .font(.system(size: 13, weight: thread.isUnread ? .semibold : .regular))
                    .lineLimit(1)
                Text(thread.snippet)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(labels.prefix(3)) { LabelChip(label: $0) }
                    }
                    .padding(.top, 3)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var senderLine: String {
        if thread.isOnlyOwnMessages {
            return thread.correspondents.isEmpty ? "(kein Empfänger)" : "An: " + thread.correspondents.joined(separator: ", ")
        }
        return thread.participants.isEmpty ? "(unbekannt)" : thread.participants.joined(separator: ", ")
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
                IconButton(systemImage: "arrow.uturn.backward", help: "Wiederherstellen", tint: .primary) { onAction(.untrash) }
            } else {
                IconButton(systemImage: "archivebox", help: "Archivieren", tint: .primary) { onAction(.archive) }
                IconButton(systemImage: "trash", help: "In den Papierkorb", tint: .primary) { onAction(.trash) }
            }
            IconButton(
                systemImage: thread.isUnread ? "envelope.open" : "envelope.badge",
                help: thread.isUnread ? "Als gelesen markieren" : "Als ungelesen markieren",
                tint: .primary
            ) { onAction(thread.isUnread ? .markRead : .markUnread) }
            IconButton(
                systemImage: thread.isStarred ? "star.fill" : "star",
                help: thread.isStarred ? "Markierung entfernen" : "Markieren",
                tint: thread.isStarred ? .accentColor : .primary
            ) { onAction(thread.isStarred ? .unstar : .star) }
        }
        .padding(.horizontal, 2)
        .background(.regularMaterial, in: Capsule())
    }
}
