import AppKit
import MailmegKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.section == .calendar, let calendarView = model.calendarView {
            // The calendar takes the whole width next to the sidebar.
            NavigationSplitView {
                CalendarSidebarView(view: calendarView)
                    .navigationSplitViewColumnWidth(min: 220, ideal: 256, max: 340)
            } detail: {
                CalendarMainView(view: calendarView)
            }
        } else {
            mail
        }
    }

    private var mail: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 236, max: 320)
        } content: {
            Group {
                if let mailbox = model.mailbox {
                    ThreadListView(mailbox: mailbox)
                } else {
                    ContentUnavailableView(tr("Kein Postfach ausgewählt", "No Mailbox Selected"), systemImage: "tray")
                        .glassBackground(.list)
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 560)
        } detail: {
            if model.isMultipleSelection, let mailbox = model.mailbox {
                MultiSelectionView(mailbox: mailbox)
            } else if let detail = model.threadDetail {
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
        .glassBackground(.canvas)
    }
}

/// Shown instead of a conversation while several are selected: what is selected and
/// what can be done with all of them at once.
private struct MultiSelectionView: View {
    @Environment(AppModel.self) private var model
    let mailbox: MailboxModel

    var body: some View {
        let threads = model.selectedThreads
        let unread = threads.filter(\.isUnread).count
        VStack(spacing: 18) {
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.cardFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.hairline.opacity(0.6), lineWidth: 0.8)
                        )
                        .overlay {
                            if index == 2 {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(LinearGradient(colors: [Palette.periwinkle, Palette.violet], startPoint: .top, endPoint: .bottom))
                            }
                        }
                        .frame(width: 92, height: 64)
                        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                        .rotationEffect(.degrees(Double(index - 2) * 6))
                        .offset(x: CGFloat(index - 2) * 5, y: CGFloat(2 - index) * 3)
                }
            }
            .frame(height: 90)

            VStack(spacing: 4) {
                Text(tr("\(threads.count) Konversationen ausgewählt", "\(threads.count) conversations selected"))
                    .font(.system(size: 18, weight: .bold))
                    .accessibilityIdentifier("selection.count")
                Text(unread > 0 ? tr("davon \(unread) ungelesen", "\(unread) of them unread") : tr("alle gelesen", "all read"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }

            let items = actions(threads: threads, unread: unread)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons(items) }
                VStack(spacing: 8) {
                    HStack(spacing: 8) { buttons(Array(items.prefix(3))) }
                    HStack(spacing: 8) { buttons(Array(items.dropFirst(3))) }
                }
            }

            Button(tr("Auswahl aufheben", "Deselect All")) { model.clearThreadSelection() }
                .buttonStyle(.link)
                .font(.system(size: 12.5))
                .accessibilityIdentifier("selection.clear")
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassBackground(.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("selection.view")
    }

    private struct Item {
        let title: String
        let systemImage: String
        let identifier: String
        let action: ThreadAction
    }

    private func actions(threads: [ThreadSummary], unread: Int) -> [Item] {
        var items: [Item] = []
        if mailbox.labelID == SystemLabel.trash {
            items.append(Item(title: tr("Wiederherstellen", "Restore"), systemImage: "arrow.uturn.backward", identifier: "selection.restore", action: .untrash))
        } else if mailbox.labelID == SystemLabel.spam {
            items.append(Item(title: tr("Kein Spam", "Not Spam"), systemImage: "checkmark.shield", identifier: "selection.notSpam", action: .notSpam))
        } else {
            items.append(Item(title: tr("Archivieren", "Archive"), systemImage: "archivebox", identifier: "selection.archive", action: .archive))
            items.append(Item(title: tr("Löschen", "Delete"), systemImage: "trash", identifier: "selection.trash", action: .trash))
        }
        items.append(unread > 0
            ? Item(title: tr("Gelesen", "Read"), systemImage: "envelope.open", identifier: "selection.read", action: .markRead)
            : Item(title: tr("Ungelesen", "Unread"), systemImage: "envelope.badge", identifier: "selection.read", action: .markUnread))
        let allStarred = !threads.isEmpty && threads.allSatisfy(\.isStarred)
        items.append(allStarred
            ? Item(title: tr("Entmarkieren", "Unstar"), systemImage: "star.slash", identifier: "selection.star", action: .unstar)
            : Item(title: tr("Markieren", "Star"), systemImage: "star", identifier: "selection.star", action: .star))
        if mailbox.labelID != SystemLabel.spam && mailbox.labelID != SystemLabel.trash {
            items.append(Item(title: tr("Spam", "Spam"), systemImage: "xmark.octagon", identifier: "selection.spam", action: .reportSpam))
        }
        return items
    }

    @ViewBuilder
    private func buttons(_ items: [Item]) -> some View {
        ForEach(items, id: \.identifier) { item in
            GlassCapsuleButton(title: item.title, systemImage: item.systemImage) {
                model.performOnSelection(item.action)
            }
            .accessibilityIdentifier(item.identifier)
        }
    }
}
