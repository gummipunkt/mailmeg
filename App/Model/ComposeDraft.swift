import Foundation
import MailmegKit

/// Value passed to a compose window. Codable so SwiftUI can restore the window.
struct ComposeDraft: Codable, Hashable, Identifiable {
    var id = UUID()
    var accountID: String
    var kind: ComposeKind = .new
    var to = ""
    var cc = ""
    var bcc = ""
    var subject = ""
    var body = ""
    /// The body with formatting from the rich-text editor; nil while nothing is formatted.
    var richBody: [RichTextRun]?
    var threadID: String?
    var inReplyTo: String?
    var references: [String] = []
    var forwardedAttachments: [AttachmentInfo] = []
    /// The address to send from (one of the account's Gmail "Send mail as" addresses).
    var fromAddress: String?
    /// The signature text that was inserted into `body`, so it can be swapped
    /// when the sender changes and rendered as HTML when sending.
    var signatureBlock = ""
    /// Where the cursor goes when the window opens (UTF-16 offset into `body`).
    var cursorOffset = 0
    /// ID of the saved Gmail draft, once the message has been saved.
    var gmailDraftID: String?
}

/// One address a message can be sent from.
struct SenderIdentity: Hashable, Identifiable {
    let accountID: String
    let address: String
    let name: String?
    let replyTo: String?
    let signatureHTML: String?

    var id: String { "\(accountID)|\(address.lowercased())" }

    var label: String {
        guard let name, !name.isEmpty else { return address }
        return "\(name) <\(address)>"
    }

    var plainSignature: String {
        guard let signatureHTML, !signatureHTML.isEmpty else { return "" }
        return HTMLText.plainText(fromHTML: signatureHTML)
    }
}

/// Lays out new messages and replies: signature, quote and the cursor position,
/// following the "reply above/below the quote" and signature settings.
@MainActor
enum DraftComposer {
    static func signatureBlock(for identity: SenderIdentity?, kind: ComposeKind) -> String {
        guard AppSettings.signatureEnabled else { return "" }
        if kind != .new, !AppSettings.signatureInReplies { return "" }
        let signature = identity?.plainSignature ?? ""
        return signature.isEmpty ? "" : "-- \n" + signature
    }

    /// Returns the body text and the cursor offset (UTF-16) for a draft.
    static func layout(kind: ComposeKind, quote: String, signature: String) -> (body: String, cursor: Int) {
        if quote.isEmpty {
            return (signature.isEmpty ? "" : "\n\n" + signature, 0)
        }
        if kind == .forward || AppSettings.replyPosition == .above {
            let signaturePart = signature.isEmpty ? "" : signature + "\n\n"
            return ("\n\n" + signaturePart + quote + "\n", 0)
        }
        let head = quote + "\n\n"
        let tail = signature.isEmpty ? "" : "\n\n" + signature
        return (head + tail, head.utf16.count)
    }

    static func newDraft(account: AccountSession?, to recipient: String = "") -> ComposeDraft {
        var draft = ComposeDraft(accountID: account?.id ?? "")
        draft.to = recipient
        guard let account else { return draft }
        let identity = account.defaultIdentity
        draft.fromAddress = identity.address
        draft.signatureBlock = signatureBlock(for: identity, kind: .new)
        (draft.body, draft.cursorOffset) = layout(kind: .new, quote: "", signature: draft.signatureBlock)
        return draft
    }

    /// Inserts `text` at the draft's cursor position (used by the quick reply field).
    static func insert(_ text: String, into draft: ComposeDraft) -> String {
        let body = draft.body
        let offset = min(max(draft.cursorOffset, 0), body.utf16.count)
        let index = String.Index(utf16Offset: offset, in: body)
        return String(body[..<index]) + text + String(body[index...])
    }

    /// Replaces the signature after the sender changed.
    static func swapSignature(in draft: inout ComposeDraft, to identity: SenderIdentity) {
        let newBlock = signatureBlock(for: identity, kind: draft.kind)
        let oldBlock = draft.signatureBlock
        if !oldBlock.isEmpty, let range = draft.body.range(of: oldBlock) {
            if newBlock.isEmpty {
                var lower = range.lowerBound
                // Also drop the blank line that separated the signature.
                if draft.body[..<lower].hasSuffix("\n\n") {
                    lower = draft.body.index(lower, offsetBy: -2)
                }
                draft.body.removeSubrange(lower..<range.upperBound)
            } else {
                draft.body.replaceSubrange(range, with: newBlock)
            }
        } else if oldBlock.isEmpty, !newBlock.isEmpty {
            draft.body += "\n\n" + newBlock
        }
        draft.signatureBlock = newBlock
    }
}

extension DraftComposer {
    /// Turns a Gmail draft message back into an editable draft.
    static func editableDraft(from message: GmailMessage, in thread: [GmailMessage], account: AccountSession) async -> ComposeDraft {
        let content = MessageContent(message: message)
        let isReply = thread.contains { !$0.isDraft && $0.id != message.id }
        var draft = ComposeDraft(accountID: account.id, kind: isReply ? .reply : .new)
        draft.to = message.to.map(\.formatted).joined(separator: ", ")
        draft.cc = message.cc.map(\.formatted).joined(separator: ", ")
        draft.bcc = message.bcc.map(\.formatted).joined(separator: ", ")
        draft.subject = message.subject
        draft.body = content.quotableText
        let identity = account.identity(for: message.from?.address)
        draft.fromAddress = identity.address
        let block = signatureBlock(for: identity, kind: draft.kind)
        draft.signatureBlock = (!block.isEmpty && draft.body.contains(block)) ? block : ""
        if isReply {
            draft.threadID = message.threadId
            draft.inReplyTo = message.header("In-Reply-To")
            draft.references = message.references
        }
        draft.forwardedAttachments = content.visibleAttachments
        draft.gmailDraftID = try? await account.draftID(forMessageID: message.id)
        return draft
    }
}

/// Saves the compose window's content as a Gmail draft a few seconds after the last
/// change, and once more when the window closes.
@MainActor
@Observable
final class DraftAutosaver {
    enum Status: Equatable {
        case idle, saving, saved(Date), failed
    }

    private(set) var status: Status = .idle
    private(set) var draftID: String?
    private let initialFingerprint: Int
    private var lastSavedFingerprint: Int?
    private var pending: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    private var attachmentCache: [String: Data] = [:]
    private var finished = false

    init(draft: ComposeDraft) {
        draftID = draft.gmailDraftID
        initialFingerprint = Self.fingerprint(draft, attachments: [])
    }

    /// Call after every change; saves after a short pause.
    func schedule(_ draft: ComposeDraft, attachments: [OutgoingAttachment], account: AccountSession?) {
        guard !finished, let account else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await self?.save(draft, attachments: attachments, account: account)
        }
    }

    /// Saves now (⌘S, window closing). Unchanged drafts are not saved.
    func save(_ draft: ComposeDraft, attachments: [OutgoingAttachment], account: AccountSession?) async {
        guard !finished, let account else { return }
        pending?.cancel()
        let previous = inFlight
        let job = Task { [weak self] in
            await previous?.value
            await self?.performSave(draft, attachments: attachments, account: account)
        }
        inFlight = job
        await job.value
    }

    private func performSave(_ draft: ComposeDraft, attachments: [OutgoingAttachment], account: AccountSession) async {
        let fingerprint = Self.fingerprint(draft, attachments: attachments)
        guard !finished, fingerprint != lastSavedFingerprint else { return }
        // Opening a window and closing it again without typing does not create a draft.
        guard draftID != nil || fingerprint != initialFingerprint else { return }

        status = .saving
        do {
            var cache = attachmentCache
            let raw = try await MailSender.rfc822(for: draft, attachments: attachments, account: account, cache: &cache)
            attachmentCache = cache
            let saved: GmailDraft
            if let draftID {
                saved = try await account.client.updateDraft(id: draftID, rfc822: raw, threadID: draft.threadID)
            } else {
                saved = try await account.client.createDraft(rfc822: raw, threadID: draft.threadID)
            }
            draftID = saved.id
            if let messageID = saved.message?.id {
                account.rememberDraft(id: saved.id, messageID: messageID)
            }
            lastSavedFingerprint = fingerprint
            status = .saved(Date())
        } catch {
            account.noteRateLimit(error)
            status = .failed
        }
    }

    /// Stops autosaving (before sending or discarding) and waits for a running save.
    func finish() async {
        finished = true
        pending?.cancel()
        await inFlight?.value
    }

    /// Resumes autosaving, e.g. after sending failed.
    func resume() {
        finished = false
    }

    /// Deletes the saved Gmail draft.
    func discard(account: AccountSession?) async {
        await finish()
        guard let draftID, let account else { return }
        try? await account.client.deleteDraft(id: draftID)
        account.forgetDraft(id: draftID)
        self.draftID = nil
    }

    private static func fingerprint(_ draft: ComposeDraft, attachments: [OutgoingAttachment]) -> Int {
        var hasher = Hasher()
        hasher.combine(draft.to)
        hasher.combine(draft.cc)
        hasher.combine(draft.bcc)
        hasher.combine(draft.subject)
        hasher.combine(draft.body)
        hasher.combine(draft.richBody)
        hasher.combine(draft.fromAddress)
        hasher.combine(draft.forwardedAttachments.map(\.id))
        for attachment in attachments {
            hasher.combine(attachment.filename)
            hasher.combine(attachment.data.count)
        }
        return hasher.finalize()
    }
}
