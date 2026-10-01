import AppKit
import MailmegKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 236, max: 320)
        } content: {
            Group {
                if let mailbox = model.mailbox {
                    ThreadListView(mailbox: mailbox)
                } else {
                    ContentUnavailableView(tr("Kein Postfach ausgewählt", "No Mailbox Selected"), systemImage: "tray")
                        .themedWindowBackground(Theme.listBackground)
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 560)
        } detail: {
            if let detail = model.threadDetail {
                ThreadDetailView(detail: detail)
                    .id(detail.threadID)
            } else {
                EmptyDetailView(unread: model.mailbox?.unreadCount ?? 0)
            }
        }
    }
}

private struct EmptyDetailView: View {
    let unread: Int

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
                .opacity(0.9)
            Text(unread > 0
                ? tr("\(unread) ungelesene Konversation\(unread == 1 ? "" : "en")", "\(unread) unread conversation\(unread == 1 ? "" : "s")")
                : tr("Alles erledigt", "All done"))
                .font(.system(size: 17, weight: .semibold))
            Text(tr("Wähle eine E-Mail aus der Liste aus.", "Select an email from the list."))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedWindowBackground(Theme.canvas)
    }
}
