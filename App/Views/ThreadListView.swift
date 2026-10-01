import MailmegKit
import SwiftUI

struct ThreadListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Bindable var mailbox: MailboxModel

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedThreadID) {
            ForEach(mailbox.threads) { thread in
                ThreadRow(thread: thread)
                    .tag(Optional(thread.id))
                    .onAppear { mailbox.loadMoreIfNeeded(after: thread) }
                    .contextMenu { contextMenu(for: thread) }
            }
            if mailbox.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if mailbox.isLoading && mailbox.threads.isEmpty {
                ProgressView()
            } else if mailbox.hasLoaded && mailbox.threads.isEmpty {
                if mailbox.activeQuery.isEmpty {
                    ContentUnavailableView("No Conversations", systemImage: "tray")
                } else {
                    ContentUnavailableView.search(text: mailbox.activeQuery)
                }
            }
        }
        .searchable(text: $mailbox.searchText, placement: .toolbar, prompt: "Search (Gmail syntax)")
        .onSubmit(of: .search) { mailbox.submitSearch() }
        .onChange(of: mailbox.searchText) { _, newValue in
            if newValue.isEmpty, !mailbox.activeQuery.isEmpty {
                mailbox.submitSearch()
            }
        }
        .navigationTitle(mailbox.title)
        .navigationSubtitle(mailbox.account.email)
    }

    @ViewBuilder
    private func contextMenu(for thread: ThreadSummary) -> some View {
        Button(thread.isUnread ? "Mark as Read" : "Mark as Unread") {
            model.perform(thread.isUnread ? .markRead : .markUnread, threadID: thread.id)
        }
        Button(thread.isStarred ? "Remove Star" : "Add Star") {
            model.perform(thread.isStarred ? .unstar : .star, threadID: thread.id)
        }
        Divider()
        if mailbox.labelID == SystemLabel.trash {
            Button("Restore") { model.perform(.untrash, threadID: thread.id) }
        } else if mailbox.labelID == SystemLabel.spam {
            Button("Not Spam") { model.perform(.notSpam, threadID: thread.id) }
        } else {
            if thread.labelIDs.contains(SystemLabel.inbox) {
                Button("Archive") { model.perform(.archive, threadID: thread.id) }
            } else {
                Button("Move to Inbox") { model.perform(.moveToInbox, threadID: thread.id) }
            }
            Button("Report Spam") { model.perform(.reportSpam, threadID: thread.id) }
            Button("Move to Trash") { model.perform(.trash, threadID: thread.id) }
        }
    }
}

struct ThreadRow: View {
    let thread: ThreadSummary

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(thread.isUnread ? Color.accentColor : .clear)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(senderLine)
                        .font(.headline)
                        .fontWeight(thread.isUnread ? .bold : .regular)
                        .lineLimit(1)
                    if thread.messageCount > 1 {
                        Text("\(thread.messageCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    if thread.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if thread.isStarred {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                    Text(Formatting.listDate(thread.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(thread.subject.isEmpty ? String(localized: "(no subject)") : thread.subject)
                    .font(.subheadline)
                    .fontWeight(thread.isUnread ? .semibold : .regular)
                    .lineLimit(1)
                Text(thread.snippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var senderLine: String {
        thread.participants.isEmpty ? String(localized: "(unknown)") : thread.participants.joined(separator: ", ")
    }
}
