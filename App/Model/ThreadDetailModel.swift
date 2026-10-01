import AppKit
import Foundation
import MailmegKit
import Observation

struct MessageItem: Identifiable {
    var message: GmailMessage
    let content: MessageContent
    /// HTML ready for display: inline `cid:` images are replaced by data URLs.
    var displayHTML: String
    var isExpanded: Bool
    var allowsRemoteContent: Bool

    var id: String { message.id }

    var hasRemoteContent: Bool {
        guard content.html != nil else { return false }
        let lower = displayHTML.lowercased()
        return lower.contains("src=\"http") || lower.contains("src='http") || lower.contains("url(http")
            || lower.contains("background=\"http") || lower.contains("srcset=\"http")
    }
}

/// A full conversation, loaded for the detail pane.
@MainActor
@Observable
final class ThreadDetailModel {
    let account: AccountSession
    let threadID: String

    private(set) var subject = ""
    var messages: [MessageItem] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    var onMarkedRead: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    init(account: AccountSession, threadID: String) {
        self.account = account
        self.threadID = threadID
    }

    var isStarred: Bool { messages.contains { $0.message.isStarred } }
    var isUnread: Bool { messages.contains { $0.message.isUnread } }
    var latestMessage: GmailMessage? { messages.last?.message }

    func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let thread = try await account.client.thread(id: threadID, format: .full)
            let gmailMessages = thread.messages ?? []
            subject = gmailMessages.first?.subject ?? ""
            let allowRemote = UserDefaults.standard.bool(forKey: AppSettings.loadRemoteContentKey)
            messages = gmailMessages.enumerated().map { index, message in
                let content = MessageContent(message: message)
                return MessageItem(
                    message: message,
                    content: content,
                    displayHTML: content.html ?? "",
                    isExpanded: index == gmailMessages.count - 1 || message.isUnread,
                    allowsRemoteContent: allowRemote
                )
            }
            await resolveInlineImages()
            await markReadIfNeeded()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func resolveInlineImages() async {
        for index in messages.indices {
            let item = messages[index]
            guard item.content.html != nil else { continue }
            var html = item.displayHTML
            for part in item.content.parts {
                guard let contentID = part.contentID, html.contains("cid:\(contentID)") else { continue }
                guard let data = try? await data(for: part) else { continue }
                html = html.replacingOccurrences(of: "cid:\(contentID)", with: "data:\(part.mimeType);base64,\(data.base64EncodedString())")
            }
            messages[index].displayHTML = html
        }
    }

    private func markReadIfNeeded() async {
        guard isUnread else { return }
        do {
            try await account.client.modifyThread(id: threadID, remove: [SystemLabel.unread])
            for index in messages.indices {
                messages[index].message.labelIds?.removeAll { $0 == SystemLabel.unread }
            }
            onMarkedRead?(threadID)
            try? await account.loadLabels()
        } catch {
            onError?(error)
        }
    }

    // MARK: - Attachments

    func data(for attachment: AttachmentInfo) async throws -> Data {
        if let inline = attachment.inlineData { return inline }
        guard let attachmentID = attachment.attachmentID else {
            throw GmailAPIError(status: 0, message: "The attachment has no data.", reason: nil)
        }
        return try await account.client.attachment(messageID: attachment.messageID, attachmentID: attachmentID)
    }

    func open(_ attachment: AttachmentInfo) async {
        do {
            let data = try await data(for: attachment)
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("Attachments", isDirectory: true)
                .appendingPathComponent(attachment.messageID, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(Self.safeFilename(attachment.filename))
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.open(url)
        } catch {
            onError?(error)
        }
    }

    func save(_ attachment: AttachmentInfo) async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Self.safeFilename(attachment.filename)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try await data(for: attachment)
            try data.write(to: url, options: .atomic)
        } catch {
            onError?(error)
        }
    }

    static func safeFilename(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return cleaned.isEmpty ? "attachment" : cleaned
    }

    // MARK: - Compose

    func draft(_ kind: ComposeKind, messageID: String? = nil) -> ComposeDraft? {
        guard let item = messageID.flatMap({ id in messages.first { $0.id == id } }) ?? messages.last else { return nil }
        let message = item.message
        let recipients = ReplyBuilder.recipients(for: message, kind: kind, selfAddresses: [account.email])
        let body = ReplyBuilder.body(
            for: message,
            quotedText: item.content.quotableText,
            kind: kind,
            dateFormatter: { $0.formatted(date: .abbreviated, time: .shortened) }
        )
        var draft = ComposeDraft(accountID: account.email, kind: kind)
        draft.to = recipients.to.map(\.formatted).joined(separator: ", ")
        draft.cc = recipients.cc.map(\.formatted).joined(separator: ", ")
        draft.subject = ReplyBuilder.subject(for: message.subject, kind: kind)
        draft.body = body
        if kind == .forward {
            draft.forwardedAttachments = item.content.visibleAttachments
        } else {
            draft.threadID = message.threadId
            draft.inReplyTo = message.messageIDHeader
            draft.references = ReplyBuilder.references(for: message)
        }
        return draft
    }
}
