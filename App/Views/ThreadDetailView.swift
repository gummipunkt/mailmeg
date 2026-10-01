import AppKit
import MailmegKit
import SwiftUI
import UniformTypeIdentifiers

struct ThreadDetailView: View {
    @Bindable var detail: ThreadDetailModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !detail.subject.isEmpty {
                    Text(detail.subject)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                        .padding(.bottom, 4)
                }
                ForEach($detail.messages) { $item in
                    MessageCardView(item: $item, detail: detail)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay {
            if detail.isLoading && detail.messages.isEmpty {
                ProgressView()
            } else if let error = detail.loadError, detail.messages.isEmpty {
                ContentUnavailableView {
                    Label("Could Not Load Conversation", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await detail.load() } }
                }
            }
        }
    }
}

struct MessageCardView: View {
    @Binding var item: MessageItem
    let detail: ThreadDetailModel
    @Environment(\.openWindow) private var openWindow
    @State private var bodyHeight: CGFloat = 40

    private var message: GmailMessage { item.message }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .contentShape(Rectangle())
                .onTapGesture { item.isExpanded.toggle() }
                .padding(12)

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

                let attachments = item.content.visibleAttachments
                if !attachments.isEmpty {
                    Divider()
                    AttachmentStrip(attachments: attachments, detail: detail)
                        .padding(12)
                }
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Avatar(name: message.from?.displayName ?? "?")
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(message.from?.displayName ?? String(localized: "(unknown)"))
                        .font(.headline)
                    if let address = message.from?.address, message.from?.name != nil {
                        Text(address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .textSelection(.enabled)
                if item.isExpanded {
                    Text(recipientLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                } else {
                    Text(HTMLText.decodeEntities(message.snippet ?? ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(Formatting.fullDate(message.date))
                .font(.caption)
                .foregroundStyle(.secondary)
            if item.isExpanded {
                Menu {
                    Button("Reply") { open(.reply) }
                    Button("Reply All") { open(.replyAll) }
                    Button("Forward") { open(.forward) }
                } label: {
                    Image(systemName: "arrowshape.turn.up.left")
                } primaryAction: {
                    open(.reply)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Reply")
            }
        }
    }

    private var recipientLine: String {
        var parts: [String] = []
        if !message.to.isEmpty {
            parts.append(String(localized: "To: ") + message.to.map(\.displayName).joined(separator: ", "))
        }
        if !message.cc.isEmpty {
            parts.append(String(localized: "Cc: ") + message.cc.map(\.displayName).joined(separator: ", "))
        }
        return parts.joined(separator: "  ·  ")
    }

    private var remoteContentBanner: some View {
        HStack {
            Image(systemName: "eye.slash")
            Text("Remote content was blocked to protect your privacy.")
            Spacer()
            Button("Load Remote Content") { item.allowsRemoteContent = true }
                .controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.15))
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

struct Avatar: View {
    let name: String

    var body: some View {
        let initial = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")).first.map { String($0).uppercased() } ?? "?"
        Circle()
            .fill(color.gradient)
            .frame(width: 32, height: 32)
            .overlay(Text(initial).font(.headline).foregroundStyle(.white))
    }

    private var color: Color {
        let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .green, .indigo, .brown]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFFFFFF }
        return palette[hash % palette.count]
    }
}

struct AttachmentStrip: View {
    let attachments: [AttachmentInfo]
    let detail: ThreadDetailModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    Button {
                        Task { await detail.open(attachment) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(nsImage: icon(for: attachment))
                                .resizable()
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(attachment.filename.isEmpty ? String(localized: "Attachment") : attachment.filename)
                                    .lineLimit(1)
                                Text(Formatting.byteCount(attachment.size))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help("Open \(attachment.filename)")
                    .contextMenu {
                        Button("Open") { Task { await detail.open(attachment) } }
                        Button("Save As…") { Task { await detail.save(attachment) } }
                    }
                }
            }
        }
    }

    private func icon(for attachment: AttachmentInfo) -> NSImage {
        let type = UTType(mimeType: attachment.mimeType)
            ?? UTType(filenameExtension: (attachment.filename as NSString).pathExtension)
            ?? .data
        return NSWorkspace.shared.icon(for: type)
    }
}
