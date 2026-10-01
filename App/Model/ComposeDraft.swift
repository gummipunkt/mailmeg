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
