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

        try await shareDriveFiles(of: draft, recipients: everyone, account: account)
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
            textBody: textBody(for: draft),
            htmlBody: htmlBody(for: draft, signatureHTML: identity.signatureHTML),
            inReplyTo: draft.inReplyTo,
            references: draft.references,
            attachments: allAttachments
        )
        return MIMEBuilder().build(message)
    }

    /// The HTML part: with the editor's formatting if there is any, otherwise from the plain text.
    static func htmlBody(for draft: ComposeDraft, signatureHTML: String?) -> String {
        let hasRuns = draft.richBody.map { $0.map(\.text).joined() == draft.body } ?? false
        if !hasRuns && draft.driveFiles.isEmpty {
            return ComposeHTML.render(text: draft.body, signatureText: draft.signatureBlock, signatureHTML: signatureHTML)
        }
        var runs = hasRuns ? (draft.richBody ?? []) : [RichTextRun(text: draft.body)]
        if !draft.driveFiles.isEmpty {
            let (before, after) = RichTextHTML.split(runs, atUTF16: driveInsertionOffset(in: draft))
            runs = before + driveRuns(draft.driveFiles) + after
        }
        return RichTextHTML.render(runs: runs, signatureText: draft.signatureBlock, signatureHTML: signatureHTML)
    }

    /// The plain-text part, with the Drive links written out.
    static func textBody(for draft: ComposeDraft) -> String {
        guard !draft.driveFiles.isEmpty else { return draft.body }
        let offset = driveInsertionOffset(in: draft)
        let index = String.Index(utf16Offset: offset, in: draft.body)
        let lines = draft.driveFiles.map { "• \($0.name) (\(Formatting.byteCount($0.size))): \($0.url)" }
        let block = "\n" + tr("Google Drive:", "Google Drive:") + "\n" + lines.joined(separator: "\n") + "\n"
        return String(draft.body[..<index]) + block + String(draft.body[index...])
    }

    /// Where the Drive links go: before the signature, else before a quoted message, else at the end.
    static func driveInsertionOffset(in draft: ComposeDraft) -> Int {
        let body = draft.body
        if !draft.signatureBlock.isEmpty, let range = body.range(of: draft.signatureBlock) {
            return body.utf16.distance(from: body.startIndex, to: range.lowerBound)
        }
        if let quote = body.range(of: "\n>") {
            // Keep the "On … wrote:" line together with the quote.
            let lineStart = body[..<quote.lowerBound].lastIndex(of: "\n") ?? quote.lowerBound
            return body.utf16.distance(from: body.startIndex, to: lineStart)
        }
        return body.utf16.count
    }

    private static func driveRuns(_ files: [DriveLink]) -> [RichTextRun] {
        var runs = [RichTextRun(text: "\n"), RichTextRun(text: "Google Drive:", isBold: true), RichTextRun(text: "\n")]
        for file in files {
            runs.append(RichTextRun(text: RichTextHTML.bulletPrefix))
            runs.append(RichTextRun(text: file.name, link: file.url))
            runs.append(RichTextRun(text: " (\(Formatting.byteCount(file.size)))\n"))
        }
        return runs
    }

    /// Opens the Drive files for the recipients before the message goes out.
    private static func shareDriveFiles(of draft: ComposeDraft, recipients: [EmailAddress], account: AccountSession) async throws {
        for file in draft.driveFiles {
            switch draft.driveSharing {
            case .anyoneWithLink:
                try await account.drive.shareWithAnyone(fileID: file.id)
            case .recipients:
                try await account.drive.share(fileID: file.id, with: recipients.map(\.address))
            }
        }
    }
}
