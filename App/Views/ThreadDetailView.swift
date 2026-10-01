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
            .padding(.vertical, 22)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
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
        .toolbar { toolbar }
        .themedWindowBackground(Theme.canvas)
    }

    @ViewBuilder
    private var header: some View {
        if !detail.subject.isEmpty || !detail.messages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(detail.subject.isEmpty ? tr("(kein Betreff)", "(no subject)") : detail.subject)
                    .font(.system(size: 22, weight: .bold))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("detail.subject")
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
            .padding(.bottom, 6)
        }
    }

    private var metaLine: String {
        let count = detail.messages.count
        let messages = count == 1 ? tr("1 Nachricht", "1 message") : tr("\(count) Nachrichten", "\(count) messages")
        let people = detail.participantCount
        return people > 2 ? tr("\(messages) · \(people) Beteiligte", "\(messages) · \(people) people") : messages
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            ControlGroup {
                Button {
                    if let draft = detail.draft(.reply) { openWindow(value: draft) }
                } label: {
                    Label(tr("Antworten", "Reply"), systemImage: "arrowshape.turn.up.left")
                }
                .help(tr("Antworten (⌘R)", "Reply (⌘R)"))
                Button {
                    if let draft = detail.draft(.replyAll) { openWindow(value: draft) }
                } label: {
                    Label(tr("Allen antworten", "Reply All"), systemImage: "arrowshape.turn.up.left.2")
                }
                .help(tr("Allen antworten (⇧⌘R)", "Reply All (⇧⌘R)"))
                Button {
                    if let draft = detail.draft(.forward) { openWindow(value: draft) }
                } label: {
                    Label(tr("Weiterleiten", "Forward"), systemImage: "arrowshape.turn.up.right")
                }
                .help(tr("Weiterleiten (⇧⌘F)", "Forward (⇧⌘F)"))
            }

            Button {
                model.perform(.archive)
            } label: {
                Label(tr("Archivieren", "Archive"), systemImage: "archivebox")
            }
            .help(tr("Archivieren (⌃⌘A)", "Archive (⌃⌘A)"))

            Button {
                model.perform(.trash)
            } label: {
                Label(tr("Löschen", "Delete"), systemImage: "trash")
            }
            .help(tr("In den Papierkorb (⌘⌫)", "Move to Trash (⌘⌫)"))

            Button {
                model.toggleRead()
            } label: {
                Label(tr("Gelesen/Ungelesen", "Read/Unread"), systemImage: model.selectedThread?.isUnread == true ? "envelope.open" : "envelope.badge")
            }
            .help(tr("Als gelesen/ungelesen markieren (⇧⌘U)", "Mark as Read/Unread (⇧⌘U)"))

            Button {
                model.toggleStar()
            } label: {
                Label(tr("Markieren", "Star"), systemImage: model.selectedThread?.isStarred == true ? "star.fill" : "star")
            }
            .help(tr("Markieren (⇧⌘L)", "Star (⇧⌘L)"))
        }
    }
}

// MARK: - Message card

struct MessageCardView: View {
    @Binding var item: MessageItem
    let detail: ThreadDetailModel
    @Environment(\.openWindow) private var openWindow
    @State private var bodyHeight: CGFloat = 60

    private var message: GmailMessage { item.message }
    private var senderName: String { message.from?.displayName ?? tr("(unbekannt)", "(unknown)") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.vertical, item.isExpanded ? 14 : 11)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy(duration: 0.2)) { item.isExpanded.toggle() } }

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
                    HStack(alignment: .center, spacing: 8) {
                        Text(recipientLine)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 8)
                        HStack(spacing: 0) {
                            IconButton(systemImage: "arrowshape.turn.up.left", help: tr("Antworten", "Reply")) { open(.reply) }
                            IconButton(systemImage: "arrowshape.turn.up.left.2", help: tr("Allen antworten", "Reply All")) { open(.replyAll) }
                            IconButton(systemImage: "arrowshape.turn.up.right", help: tr("Weiterleiten", "Forward")) { open(.forward) }
                        }
                        .fixedSize()
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

    private var recipientLine: String {
        var parts: [String] = []
        if let address = message.from?.address, message.from?.name != nil {
            parts.append(address)
        }
        if !message.to.isEmpty {
            parts.append(tr("an ", "to ") + message.to.map { $0.address == detail.account.email ? tr("mich", "me") : $0.displayName }.joined(separator: ", "))
        }
        if !message.cc.isEmpty {
            parts.append("Cc " + message.cc.map(\.displayName).joined(separator: ", "))
        }
        return parts.joined(separator: " · ")
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
        var draft = ComposeDraft(accountID: detail.account.email)
        draft.to = components?.path.removingPercentEncoding ?? ""
        for item in components?.queryItems ?? [] {
            switch item.name.lowercased() {
            case "subject": draft.subject = item.value ?? ""
            case "body": draft.body = item.value ?? ""
            case "cc": draft.cc = item.value ?? ""
            case "bcc": draft.bcc = item.value ?? ""
            default: break
            }
        }
        openWindow(value: draft)
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
                draft.body = text + draft.body
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
        .background(Theme.canvas)
        .overlay(alignment: .top) { Divider() }
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
