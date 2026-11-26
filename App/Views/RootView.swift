import AppKit
import MailmegKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
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
        // Behind the glass sidebar of macOS 26 the window itself carries the backdrop.
        .windowBackdrop()
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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .floatingPanel()
                        .padding(.horizontal, 8)
                        .padding(.top, 2)
                        .padding(.bottom, 10)
                        .glassBackground(.list)
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 560)
        } detail: {
            MailDetailColumn()
        }
    }
}

/// The reading pane with its part of the window toolbar: the actions for the selected
/// conversation (or for all selected ones).
private struct MailDetailColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if model.isMultipleSelection, let mailbox = model.mailbox {
                MultiSelectionView(mailbox: mailbox)
            } else if let detail = model.threadDetail {
                ThreadDetailView(detail: detail)
                    .id(detail.threadID)
            } else {
                EmptyDetailView(unread: model.mailbox?.unreadCount ?? 0)
            }
        }
        .toolbar { toolbar }
    }

    private var thread: ThreadSummary? { model.selectedThread }
    private var hasThread: Bool { model.threadDetail != nil && !model.isMultipleSelection }
    private var isInTrash: Bool { model.mailbox?.labelID == SystemLabel.trash || thread?.labelIDs.contains(SystemLabel.trash) == true }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { compose(.reply) } label: {
                Label(tr("Antworten", "Reply"), systemImage: "arrowshape.turn.up.left")
            }
            .help(tr("Antworten (⌘R)", "Reply (⌘R)"))
            .disabled(!hasThread)
            .accessibilityIdentifier("detail.reply")
            Button { compose(.replyAll) } label: {
                Label(tr("Allen antworten", "Reply All"), systemImage: "arrowshape.turn.up.left.2")
            }
            .help(tr("Allen antworten (⇧⌘R)", "Reply All (⇧⌘R)"))
            .disabled(!hasThread)
            .accessibilityIdentifier("detail.replyAll")
            Button { compose(.forward) } label: {
                Label(tr("Weiterleiten", "Forward"), systemImage: "arrowshape.turn.up.right")
            }
            .help(tr("Weiterleiten (⇧⌘F)", "Forward (⇧⌘F)"))
            .disabled(!hasThread)
            .accessibilityIdentifier("detail.forward")
        }
        ToolbarGroupGap()
        ToolbarItemGroup {
            if isInTrash {
                Button { model.perform(.untrash) } label: {
                    Label(tr("Wiederherstellen", "Restore"), systemImage: "arrow.uturn.backward")
                }
                .help(tr("Wiederherstellen", "Restore"))
                .disabled(!model.hasThreadSelection)
                .accessibilityIdentifier("detail.restore")
            } else {
                Button { model.perform(.archive) } label: {
                    Label(tr("Archivieren", "Archive"), systemImage: "archivebox")
                }
                .help(tr("Archivieren (⌃⌘A)", "Archive (⌃⌘A)"))
                .disabled(!model.hasThreadSelection)
                .accessibilityIdentifier("detail.archive")
                Button { model.perform(.trash) } label: {
                    Label(tr("Löschen", "Delete"), systemImage: "trash")
                }
                .help(tr("In den Papierkorb (⌘⌫)", "Move to Trash (⌘⌫)"))
                .disabled(!model.hasThreadSelection)
                .accessibilityIdentifier("detail.trash")
            }
        }
        ToolbarGroupGap()
        ToolbarItemGroup {
            labelsMenu
            Button { model.toggleRead() } label: {
                Label(
                    model.selectedThreads.contains(where: \.isUnread) ? tr("Als gelesen markieren", "Mark as Read") : tr("Als ungelesen markieren", "Mark as Unread"),
                    systemImage: model.selectedThreads.contains(where: \.isUnread) ? "envelope.open" : "envelope.badge"
                )
            }
            .help(tr("Als gelesen/ungelesen markieren (⇧⌘U)", "Mark as Read/Unread (⇧⌘U)"))
            .disabled(!model.hasThreadSelection)
            .accessibilityIdentifier("detail.read")
        }
        ToolbarFlexibleGap()
        ToolbarItem {
            moreMenu
        }
    }

    private var labelsMenu: some View {
        let userLabels = (model.mailbox?.account.labels ?? [])
            .filter { !$0.isSystem && !$0.isHidden }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let applied = thread?.labelIDs ?? []
        return Menu {
            if userLabels.isEmpty {
                Text(tr("Keine eigenen Labels", "No Custom Labels"))
            }
            ForEach(userLabels) { label in
                let isOn = applied.contains(label.id)
                Toggle(label.name, isOn: Binding(
                    get: { isOn },
                    set: { model.perform($0 ? .addLabel(label.id) : .removeLabel(label.id)) }
                ))
            }
        } label: {
            Label(tr("Labels", "Labels"), systemImage: "tag")
        }
        .menuIndicator(.hidden)
        .help(tr("Labels", "Labels"))
        .disabled(!hasThread)
        .accessibilityIdentifier("detail.labels")
    }

    private var moreMenu: some View {
        Menu {
            Button(thread?.isStarred == true ? tr("Markierung entfernen", "Remove Star") : tr("Markieren", "Star")) { model.toggleStar() }
            if thread?.labelIDs.contains(SystemLabel.spam) == true {
                Button(tr("Kein Spam", "Not Spam")) { model.perform(.notSpam) }
            } else {
                Button(tr("Als Spam melden", "Report Spam")) { model.perform(.reportSpam) }
            }
            if hasThread, thread?.labelIDs.contains(SystemLabel.inbox) == false {
                Button(tr("In den Posteingang", "Move to Inbox")) { model.perform(.moveToInbox) }
            }
            Divider()
            Button(tr("Termin aus E-Mail erstellen …", "Create Event from Email…")) {
                if let draft = model.eventDraftFromSelectedMessage() { openWindow(value: draft) }
            }
            .disabled(!hasThread)
            Button(tr("Alle Anhänge sichern …", "Save All Attachments…")) {
                if let detail = model.threadDetail {
                    Task { await detail.saveAll(detail.allFiles) }
                }
            }
            .disabled(!hasThread || (model.threadDetail?.allFiles.isEmpty ?? true))
            Button(tr("In Konversation suchen", "Find in Conversation")) { model.threadDetail?.beginFind() }
                .disabled(!hasThread)
            Divider()
            Button(tr("Header anzeigen", "Show Headers")) { showSource(.headers) }
                .disabled(!hasThread)
            Button(tr("Quelltext anzeigen", "Show Source")) { showSource(.source) }
                .disabled(!hasThread)
        } label: {
            Label(tr("Weitere Aktionen", "More Actions"), systemImage: "ellipsis")
        }
        .menuIndicator(.hidden)
        .help(tr("Weitere Aktionen", "More Actions"))
        .disabled(!model.hasThreadSelection)
        .accessibilityIdentifier("detail.more")
    }

    private func compose(_ kind: ComposeKind) {
        if let detail = model.threadDetail, let draft = detail.draft(kind) {
            detail.present(draft, openWindow: openWindow)
        }
    }

    private func showSource(_ mode: SourceRequest.Mode) {
        if let request = model.threadDetail?.sourceRequest(mode) { openWindow(value: request) }
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
        .detailSheet()
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
                        .fill(Theme.solidCard)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.hairline.opacity(0.6), lineWidth: 0.8)
                        )
                        .overlay {
                            if index == 2 {
                                Image(systemName: "envelope.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(Theme.accentGradient)
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
            GlassGroup {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { buttons(items) }
                    VStack(spacing: 8) {
                        HStack(spacing: 8) { buttons(Array(items.prefix(3))) }
                        HStack(spacing: 8) { buttons(Array(items.dropFirst(3))) }
                    }
                }
            }

            Button(tr("Auswahl aufheben", "Deselect All")) { model.clearThreadSelection() }
                .buttonStyle(.link)
                .font(.system(size: 12.5))
                .accessibilityIdentifier("selection.clear")
        }
        .padding(30)
        .detailSheet()
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
