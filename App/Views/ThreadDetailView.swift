import AppKit
import MailmegKit
import SwiftUI
import UniformTypeIdentifiers

struct ThreadDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Bindable var detail: ThreadDetailModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                ForEach($detail.messages) { $item in
                    MessageCardView(item: $item, detail: detail)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 22)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) { actionBar }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !detail.messages.isEmpty {
                QuickReplyBar(detail: detail)
            }
        }
        .overlay {
            if detail.isLoading && detail.messages.isEmpty {
                ProgressView()
            } else if let error = detail.loadError, detail.messages.isEmpty {
                ContentUnavailableView {
                    Label(tr("Konversation konnte nicht geladen werden", "Couldn’t Load Conversation"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button(tr("Erneut versuchen", "Try Again")) { Task { await detail.load() } }
                }
            }
        }
        .glassBackground(.canvas)
    }

    // MARK: Airmail-style action bar

    private var thread: ThreadSummary? { model.selectedThread }

    private var actionBar: some View {
        HStack(spacing: 7) {
            GlassCircleButton(systemImage: "arrowshape.turn.up.left", help: tr("Antworten (⌘R)", "Reply (⌘R)")) { compose(.reply) }
                .accessibilityIdentifier("detail.reply")
            GlassCircleButton(systemImage: "arrowshape.turn.up.left.2", help: tr("Allen antworten (⇧⌘R)", "Reply All (⇧⌘R)")) { compose(.replyAll) }
            GlassCircleButton(systemImage: "arrowshape.turn.up.right", help: tr("Weiterleiten (⇧⌘F)", "Forward (⇧⌘F)")) { compose(.forward) }

            Spacer().frame(width: 6)

            if thread?.labelIDs.contains(SystemLabel.trash) == true {
                GlassCircleButton(systemImage: "arrow.uturn.backward", help: tr("Wiederherstellen", "Restore")) { model.perform(.untrash) }
            } else {
                GlassCircleButton(systemImage: "archivebox", help: tr("Archivieren (⌃⌘A)", "Archive (⌃⌘A)")) { model.perform(.archive) }
                GlassCircleButton(systemImage: "trash", help: tr("In den Papierkorb (⌘⌫)", "Move to Trash (⌘⌫)")) { model.perform(.trash) }
            }
            labelsMenu
            GlassCircleButton(
                systemImage: thread?.isUnread == true ? "envelope.badge" : "envelope.open",
                help: tr("Als gelesen/ungelesen markieren (⇧⌘U)", "Mark as Read/Unread (⇧⌘U)"),
                isActive: thread?.isUnread == true
            ) { model.toggleRead() }

            Spacer(minLength: 6)

            GlassCircleButton(systemImage: "chevron.up", help: tr("Vorherige Konversation (⌥⌘↑)", "Previous Conversation (⌥⌘↑)")) { model.selectAdjacentThread(-1) }
                .disabled(!model.canSelectAdjacentThread(-1))
                .opacity(model.canSelectAdjacentThread(-1) ? 1 : 0.45)
                .accessibilityIdentifier("detail.previous")
            GlassCircleButton(systemImage: "chevron.down", help: tr("Nächste Konversation (⌥⌘↓)", "Next Conversation (⌥⌘↓)")) { model.selectAdjacentThread(1) }
                .disabled(!model.canSelectAdjacentThread(1))
                .opacity(model.canSelectAdjacentThread(1) ? 1 : 0.45)
                .accessibilityIdentifier("detail.next")
            moreMenu
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var labelsMenu: some View {
        let userLabels = detail.account.labels
            .filter { !$0.isSystem && !$0.isHidden }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let applied = thread?.labelIDs ?? []
        return GlassCircleMenu(systemImage: "square.grid.2x2", help: tr("Labels", "Labels")) {
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
        }
        .accessibilityIdentifier("detail.labels")
    }

    private var moreMenu: some View {
        GlassCircleMenu(systemImage: "ellipsis", help: tr("Weitere Aktionen", "More Actions")) {
            Button(thread?.isStarred == true ? tr("Markierung entfernen", "Remove Star") : tr("Markieren", "Star")) { model.toggleStar() }
            if thread?.labelIDs.contains(SystemLabel.spam) == true {
                Button(tr("Kein Spam", "Not Spam")) { model.perform(.notSpam) }
            } else {
                Button(tr("Als Spam melden", "Report Spam")) { model.perform(.reportSpam) }
            }
            if thread?.labelIDs.contains(SystemLabel.inbox) == false {
                Button(tr("In den Posteingang", "Move to Inbox")) { model.perform(.moveToInbox) }
            }
            Divider()
            Button(tr("Header anzeigen", "Show Headers")) { showSource(.headers) }
            Button(tr("Quelltext anzeigen", "Show Source")) { showSource(.source) }
        }
        .accessibilityIdentifier("detail.more")
    }

    private func compose(_ kind: ComposeKind) {
        if let draft = detail.draft(kind) { openWindow(value: draft) }
    }

    private func showSource(_ mode: SourceRequest.Mode) {
        if let request = detail.sourceRequest(mode) { openWindow(value: request) }
    }

    @ViewBuilder
    private var header: some View {
        if !detail.subject.isEmpty || !detail.messages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(detail.subject.isEmpty ? tr("(kein Betreff)", "(no subject)") : detail.subject)
                        .font(.system(size: 26, weight: .bold))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("detail.subject")
                    Spacer(minLength: 8)
                    Button {
                        model.toggleStar()
                    } label: {
                        Image(systemName: thread?.isStarred == true ? "star.fill" : "star")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(thread?.isStarred == true ? Color.accentColor : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(tr("Markieren (⇧⌘L)", "Star (⇧⌘L)"))
                }
                HStack(spacing: 6) {
                    let labelIDs = Set(detail.messages.flatMap { $0.message.labelIds ?? [] })
                    ForEach(detail.account.userLabels(in: labelIDs)) { LabelChip(label: $0) }
                    if labelIDs.contains(SystemLabel.important) {
                        Label(tr("Wichtig", "Important"), systemImage: "bookmark.fill")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(metaLine)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 8)
        }
    }

    private var metaLine: String {
        let count = detail.messages.count
        let messages = count == 1 ? tr("1 Nachricht", "1 message") : tr("\(count) Nachrichten", "\(count) messages")
        let people = detail.participantCount
        return people > 2 ? tr("\(messages) · \(people) Beteiligte", "\(messages) · \(people) people") : messages
    }
}

// MARK: - Message card

struct MessageCardView: View {
    @Binding var item: MessageItem
    let detail: ThreadDetailModel
    @Environment(\.openWindow) private var openWindow
    @State private var bodyHeight: CGFloat = 60
    @State private var showsDetails = false

    private var message: GmailMessage { item.message }
    private var senderName: String { message.from?.displayName ?? tr("(unbekannt)", "(unknown)") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, item.isExpanded ? 14 : 11)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy(duration: 0.2)) { item.isExpanded.toggle() } }

            if item.message.isDraft {
                draftBanner
            }
            if item.isExpanded {
                if item.hasRemoteContent && !item.allowsRemoteContent {
                    remoteContentBanner
                }
                HTMLMessageView(
                    html: item.content.html == nil ? nil : item.displayHTML,
                    plainText: item.content.plainText,
                    allowsRemoteContent: item.allowsRemoteContent,
                    height: $bodyHeight,
                    onMailto: openMailto
                )
                .frame(height: max(bodyHeight, 40))
                .background(item.content.html != nil ? Color.white : Color.clear)
                .padding(.horizontal, item.content.html != nil ? 0 : 4)

                let attachments = item.content.visibleAttachments
                if !attachments.isEmpty {
                    AttachmentGrid(attachments: attachments, detail: detail)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
        }
        .card()
        .opacity(item.isExpanded ? 1 : 0.92)
    }

    @ViewBuilder
    private var header: some View {
        if item.isExpanded {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(name: senderName, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(senderName)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(1)
                            .layoutPriority(1)
                        Spacer(minLength: 8)
                        Text(Formatting.fullDate(message.date))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                    .textSelection(.enabled)
                    if let address = message.from?.address {
                        Text(address)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                    HStack(alignment: .center, spacing: 8) {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { showsDetails.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text(recipientLine)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Image(systemName: showsDetails ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8.5, weight: .bold))
                            }
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(tr("Alle Empfänger und Details anzeigen", "Show all recipients and details"))
                        .accessibilityIdentifier("message.details.\(message.id)")
                        Spacer(minLength: 8)
                        HStack(spacing: 0) {
                            IconButton(systemImage: "arrowshape.turn.up.left", help: tr("Antworten", "Reply")) { open(.reply) }
                            IconButton(systemImage: "arrowshape.turn.up.left.2", help: tr("Allen antworten", "Reply All")) { open(.replyAll) }
                            IconButton(systemImage: "arrowshape.turn.up.right", help: tr("Weiterleiten", "Forward")) { open(.forward) }
                            Menu {
                                Button(tr("Header anzeigen", "Show Headers")) { showSource(.headers) }
                                Button(tr("Quelltext anzeigen", "Show Source")) { showSource(.source) }
                                Divider()
                                Button(tr("Absenderadresse kopieren", "Copy Sender Address")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(message.from?.address ?? "", forType: .string)
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, height: 22)
                            }
                            .menuStyle(.button)
                            .buttonStyle(.borderless)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help(tr("Weitere Aktionen", "More Actions"))
                        }
                        .fixedSize()
                    }
                    if showsDetails {
                        MessageDetailsGrid(message: message, ownAddress: detail.account.email)
                            .padding(.top, 6)
                            .transition(.opacity)
                    }
                }
            }
        } else {
            HStack(spacing: 10) {
                AvatarView(name: senderName, size: 26)
                Text(senderName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(HTMLText.decodeEntities(message.snippet ?? ""))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Formatting.listDate(message.date))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "to anna@example.com, me (alex@example.com)" – always with the exact address it went to.
    private var recipientLine: String {
        var parts: [String] = []
        let recipients = message.to.isEmpty ? deliveredTo.map { [$0] } ?? [] : message.to
        if !recipients.isEmpty {
            parts.append(tr("an ", "to ") + recipients.map(describe).joined(separator: ", "))
        }
        if !message.cc.isEmpty {
            parts.append("Cc " + message.cc.map(describe).joined(separator: ", "))
        }
        if !message.bcc.isEmpty {
            parts.append("Bcc " + message.bcc.map(describe).joined(separator: ", "))
        }
        return parts.isEmpty ? tr("an (unbekannt)", "to (unknown)") : parts.joined(separator: " · ")
    }

    private var deliveredTo: EmailAddress? {
        message.header("Delivered-To").flatMap { EmailAddress.parseList($0).first }
    }

    private func describe(_ address: EmailAddress) -> String {
        if address.address.caseInsensitiveCompare(detail.account.email) == .orderedSame {
            return tr("mich", "me") + " (\(address.address))"
        }
        if address.name != nil {
            return "\(address.displayName) <\(address.address)>"
        }
        return address.address
    }

    private func showSource(_ mode: SourceRequest.Mode) {
        if let request = detail.sourceRequest(mode, messageID: message.id) { openWindow(value: request) }
    }

    private var draftBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text(tr("Entwurf – noch nicht gesendet", "Draft – not sent yet"))
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Button(tr("Verwerfen", "Discard"), role: .destructive) {
                Task { await detail.discardDraft(messageID: message.id) }
            }
            .controlSize(.small)
            Button(tr("Bearbeiten", "Edit")) {
                Task {
                    if let draft = await detail.editDraft(messageID: message.id) {
                        openWindow(value: draft)
                    }
                }
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("draft.edit")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.tint)
    }

    private var remoteContentBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash.fill")
                .foregroundStyle(.secondary)
            Text(tr("Externe Inhalte wurden zum Schutz deiner Privatsphäre blockiert.", "Remote content was blocked to protect your privacy."))
                .font(.system(size: 12))
            Spacer()
            Button(tr("Laden", "Load")) { item.allowsRemoteContent = true }
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.tint)
    }

    private func open(_ kind: ComposeKind) {
        if let draft = detail.draft(kind, messageID: message.id) {
            openWindow(value: draft)
        }
    }

    private func openMailto(_ url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var draft = DraftComposer.newDraft(account: detail.account)
        draft.to = components?.path.removingPercentEncoding ?? ""
        for item in components?.queryItems ?? [] {
            switch item.name.lowercased() {
            case "subject": draft.subject = item.value ?? ""
            case "body": draft.body = (item.value ?? "") + draft.body
            case "cc": draft.cc = item.value ?? ""
            case "bcc": draft.bcc = item.value ?? ""
            default: break
            }
        }
        openWindow(value: draft)
    }
}

/// Full sender/recipient list of one message, with complete addresses (Mail's "Details").
private struct MessageDetailsGrid: View {
    let message: GmailMessage
    let ownAddress: String

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 4) {
            row(tr("Von", "From"), message.header("From"))
            row(tr("Antwort an", "Reply-To"), message.header("Reply-To"))
            row(tr("An", "To"), message.header("To"))
            row("Cc", message.header("Cc"))
            row("Bcc", message.header("Bcc"))
            row(tr("Zugestellt an", "Delivered to"), message.header("Delivered-To"))
            row(tr("Datum", "Date"), message.date.map { Formatting.fullDate($0) } ?? message.header("Date"))
            row(tr("Betreff", "Subject"), message.subject)
        }
        .font(.system(size: 11.5))
        .textSelection(.enabled)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityIdentifier("message.detailsGrid")
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            GridRow {
                Text(title)
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                Text(EmailAddress.parseList(value).isEmpty || title == tr("Datum", "Date") || title == tr("Betreff", "Subject")
                     ? value
                     : EmailAddress.parseList(value).map(format).joined(separator: ", "))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func format(_ address: EmailAddress) -> String {
        let own = address.address.caseInsensitiveCompare(ownAddress) == .orderedSame ? tr(" (ich)", " (me)") : ""
        if address.name != nil { return "\(address.displayName) <\(address.address)>\(own)" }
        return address.address + own
    }
}

// MARK: - Attachments

struct AttachmentGrid: View {
    let attachments: [AttachmentInfo]
    let detail: ThreadDetailModel

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(attachments) { attachment in
                AttachmentTile(attachment: attachment, detail: detail)
            }
        }
    }
}

private struct AttachmentTile: View {
    let attachment: AttachmentInfo
    let detail: ThreadDetailModel
    @State private var isHovering = false

    var body: some View {
        Button {
            Task { await detail.open(attachment) }
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(attachment.filename.isEmpty ? tr("Anhang", "Attachment") : attachment.filename)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(Formatting.byteCount(attachment.size))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if isHovering {
                    IconButton(systemImage: "arrow.down.circle", help: tr("Sichern unter …", "Save As…")) {
                        Task { await detail.save(attachment) }
                    }
                }
            }
            .padding(8)
            .background(Theme.tint.opacity(isHovering ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(tr("\(attachment.filename) öffnen", "Open \(attachment.filename)"))
        .contextMenu {
            Button(tr("Öffnen", "Open")) { Task { await detail.open(attachment) } }
            Button(tr("Sichern unter …", "Save As…")) { Task { await detail.save(attachment) } }
        }
    }

    private var icon: NSImage {
        let type = UTType(mimeType: attachment.mimeType)
            ?? UTType(filenameExtension: (attachment.filename as NSString).pathExtension)
            ?? .data
        return NSWorkspace.shared.icon(for: type)
    }
}

// MARK: - Quick reply

private struct QuickReplyBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    let detail: ThreadDetailModel
    @State private var text = ""
    @State private var isSending = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...8)
                .focused($isFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isFocused ? Color.accentColor.opacity(0.7) : Theme.hairline.opacity(0.6))
                )
                .accessibilityIdentifier("quickReply")

            IconButton(systemImage: "arrow.up.left.and.arrow.down.right", help: tr("Im Fenster bearbeiten", "Edit in Window")) {
                guard var draft = detail.draft(.reply) else { return }
                draft.body = DraftComposer.insert(text, into: draft)
                draft.cursorOffset += text.utf16.count
                text = ""
                openWindow(value: draft)
            }
            .padding(.bottom, 6)

            Button {
                send()
            } label: {
                if isSending {
                    ProgressView().controlSize(.small).frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .help(tr("Senden (⌘↩)", "Send (⌘↩)"))
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }

    private var placeholder: String {
        if let name = detail.replyRecipientName { return tr("Antwort an \(name) …", "Reply to \(name)…") }
        return tr("Antworten …", "Reply…")
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func send() {
        guard canSend else { return }
        let message = text
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await detail.sendQuickReply(message, replyAll: false)
                text = ""
                model.didSend(from: detail.account)
            } catch {
                model.present(error)
            }
        }
    }
}
