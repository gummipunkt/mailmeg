import MailmegKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 230, max: 320)
        } content: {
            Group {
                if let mailbox = model.mailbox {
                    ThreadListView(mailbox: mailbox)
                } else {
                    ContentUnavailableView("No Mailbox Selected", systemImage: "tray")
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 380, max: 560)
        } detail: {
            if let detail = model.threadDetail {
                ThreadDetailView(detail: detail)
                    .id(detail.threadID)
            } else {
                ContentUnavailableView("No Conversation Selected", systemImage: "envelope.open")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    openWindow(value: model.newDraft())
                } label: {
                    Label("New Message", systemImage: "square.and.pencil")
                }
                .help("New Message (⌘N)")

                Button {
                    if let draft = model.replyDraft(.reply) { openWindow(value: draft) }
                } label: {
                    Label("Reply", systemImage: "arrowshape.turn.up.left")
                }
                .disabled(model.threadDetail == nil)
                .help("Reply (⌘R)")

                Button {
                    model.perform(.archive)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .disabled(model.selectedThreadID == nil)
                .help("Archive (⌃⌘A)")

                Button {
                    model.perform(.trash)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(model.selectedThreadID == nil)
                .help("Move to Trash (⌘⌫)")

                Button {
                    model.toggleRead()
                } label: {
                    Label("Read/Unread", systemImage: model.selectedThread?.isUnread == true ? "envelope.open" : "envelope.badge")
                }
                .disabled(model.selectedThreadID == nil)
                .help("Mark as Read/Unread (⇧⌘U)")

                Button {
                    model.toggleStar()
                } label: {
                    Label("Star", systemImage: model.selectedThread?.isStarred == true ? "star.fill" : "star")
                }
                .disabled(model.selectedThreadID == nil)
                .help("Star (⇧⌘L)")

                Button {
                    Task { await model.refreshAll() }
                } label: {
                    Label("Get New Mail", systemImage: "arrow.clockwise")
                }
                .help("Get New Mail (⇧⌘N)")
            }
        }
    }
}
