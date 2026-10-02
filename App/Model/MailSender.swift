import Foundation
import MailmegKit

enum MailSenderError: LocalizedError {
    case noRecipients
    case invalidAddress(String)

    var errorDescription: String? {
        switch self {
        case .noRecipients: tr("Bitte gib mindestens einen Empfänger an.", "Please add at least one recipient.")
        case .invalidAddress(let address): tr("„\(address)“ ist keine gültige E-Mail-Adresse.", "“\(address)” is not a valid email address.")
        }
    }
}

/// Turns a draft into a MIME message and sends it through the Gmail API.
@MainActor
enum MailSender {
    static func send(_ draft: ComposeDraft, attachments: [OutgoingAttachment] = [], account: AccountSession) async throws {
        let everyone = EmailAddress.parseList(draft.to) + EmailAddress.parseList(draft.cc) + EmailAddress.parseList(draft.bcc)
        guard !everyone.isEmpty else { throw MailSenderError.noRecipients }
        if let invalid = everyone.first(where: { !$0.address.contains("@") }) {
            throw MailSenderError.invalidAddress(invalid.address)
        }

        var cache: [String: Data] = [:]
        let raw = try await rfc822(for: draft, attachments: attachments, account: account, cache: &cache)
        try await account.client.send(rfc822: raw, threadID: draft.threadID)
        // The message is out; the saved Gmail draft is no longer needed.
        if let draftID = draft.gmailDraftID {
            try? await account.client.deleteDraft(id: draftID)
            account.forgetDraft(id: draftID)
        }
    }

    /// Builds the RFC 822 message for sending or for saving as a Gmail draft.
    /// Attachments carried over from another message are downloaded once and kept in `cache`.
    static func rfc822(for draft: ComposeDraft, attachments: [OutgoingAttachment], account: AccountSession, cache: inout [String: Data]) async throws -> Data {
        var allAttachments = attachments
        for carried in draft.forwardedAttachments {
            let data: Data
            if let cached = cache[carried.id] {
                data = cached
            } else if let inline = carried.inlineData {
                data = inline
            } else if let attachmentID = carried.attachmentID {
                data = try await account.client.attachment(messageID: carried.messageID, attachmentID: attachmentID)
                cache[carried.id] = data
            } else {
                continue
            }
            allAttachments.append(OutgoingAttachment(filename: carried.filename, mimeType: carried.mimeType, data: data))
        }

        let identity = account.identity(for: draft.fromAddress)
        let message = OutgoingMessage(
            from: EmailAddress(name: identity.name ?? account.displayName, address: identity.address),
            replyTo: identity.replyTo.map { EmailAddress.parseList($0) } ?? [],
            to: EmailAddress.parseList(draft.to),
            cc: EmailAddress.parseList(draft.cc),
            bcc: EmailAddress.parseList(draft.bcc),
            subject: draft.subject,
            textBody: draft.body,
            htmlBody: htmlBody(for: draft, signatureHTML: identity.signatureHTML),
            inReplyTo: draft.inReplyTo,
            references: draft.references,
            attachments: allAttachments
        )
        return MIMEBuilder().build(message)
    }

    /// The HTML part: with the editor's formatting if there is any, otherwise from the plain text.
    static func htmlBody(for draft: ComposeDraft, signatureHTML: String?) -> String {
        if let runs = draft.richBody, runs.map(\.text).joined() == draft.body {
            return RichTextHTML.render(runs: runs, signatureText: draft.signatureBlock, signatureHTML: signatureHTML)
        }
        return ComposeHTML.render(text: draft.body, signatureText: draft.signatureBlock, signatureHTML: signatureHTML)
    }
}
