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
        let to = EmailAddress.parseList(draft.to)
        let cc = EmailAddress.parseList(draft.cc)
        let bcc = EmailAddress.parseList(draft.bcc)
        let everyone = to + cc + bcc
        guard !everyone.isEmpty else { throw MailSenderError.noRecipients }
        if let invalid = everyone.first(where: { !$0.address.contains("@") }) {
            throw MailSenderError.invalidAddress(invalid.address)
        }

        var allAttachments = attachments
        for forwarded in draft.forwardedAttachments {
            let data: Data
            if let inline = forwarded.inlineData {
                data = inline
            } else if let attachmentID = forwarded.attachmentID {
                data = try await account.client.attachment(messageID: forwarded.messageID, attachmentID: attachmentID)
            } else {
                continue
            }
            allAttachments.append(OutgoingAttachment(filename: forwarded.filename, mimeType: forwarded.mimeType, data: data))
        }

        let identity = account.identity(for: draft.fromAddress)
        let message = OutgoingMessage(
            from: EmailAddress(name: identity.name ?? account.displayName, address: identity.address),
            replyTo: identity.replyTo.map { EmailAddress.parseList($0) } ?? [],
            to: to,
            cc: cc,
            bcc: bcc,
            subject: draft.subject,
            textBody: draft.body,
            htmlBody: ComposeHTML.render(text: draft.body, signatureText: draft.signatureBlock, signatureHTML: identity.signatureHTML),
            inReplyTo: draft.inReplyTo,
            references: draft.references,
            attachments: allAttachments
        )
        try await account.client.send(rfc822: MIMEBuilder().build(message), threadID: draft.threadID)
    }
}
