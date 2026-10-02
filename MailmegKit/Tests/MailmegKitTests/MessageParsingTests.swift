import XCTest
@testable import MailmegKit

final class MessageParsingTests: XCTestCase {
    private func header(_ name: String, _ value: String) -> MessageHeader { MessageHeader(name: name, value: value) }

    private var sampleMessage: GmailMessage {
        let plain = MessagePart(
            partId: "0.0", mimeType: "text/plain", filename: "",
            headers: [header("Content-Type", "text/plain; charset=ISO-8859-1")],
            body: MessagePartBody(size: 5, data: "R3L832U=")
        )
        let html = MessagePart(
            partId: "0.1", mimeType: "text/html", filename: "",
            headers: [header("Content-Type", "text/html; charset=UTF-8")],
            body: MessagePartBody(size: 17, data: "SGFsbG8gPGI-V2VsdDwvYj4=")
        )
        let inlineImage = MessagePart(
            partId: "1", mimeType: "image/png", filename: "logo.png",
            headers: [header("Content-ID", "<logo123>"), header("Content-Disposition", "inline; filename=logo.png")],
            body: MessagePartBody(attachmentId: "att-logo", size: 100)
        )
        let attachment = MessagePart(
            partId: "2", mimeType: "application/pdf", filename: "report.pdf",
            headers: [header("Content-Disposition", "attachment; filename=\"report.pdf\"")],
            body: MessagePartBody(attachmentId: "att-pdf", size: 2048)
        )
        let alternative = MessagePart(partId: "0", mimeType: "multipart/alternative", parts: [plain, html])
        let root = MessagePart(
            partId: "", mimeType: "multipart/mixed", filename: "",
            headers: [
                header("From", "\"Doe, Jane\" <jane@example.com>"),
                header("To", "me@example.com, Bob <bob@example.com>"),
                header("Cc", "carol@example.com"),
                header("Subject", "Quarterly report"),
                header("Message-ID", "<m2@example.com>"),
                header("References", "<m1@example.com>"),
            ],
            parts: [alternative, inlineImage, attachment]
        )
        return GmailMessage(
            id: "msg1", threadId: "t1", labelIds: ["INBOX", "UNREAD"], snippet: "Hallo &amp; tsch&#252;ss",
            internalDate: "1700000000000", payload: root
        )
    }

    func testExtractsBodiesAndAttachments() {
        let content = MessageContent(message: sampleMessage)
        XCTAssertEqual(content.plainText, "Grüße")
        XCTAssertEqual(content.html, "Hallo <b>Welt</b>")
        XCTAssertEqual(content.parts.count, 2)
        XCTAssertEqual(content.visibleAttachments.map(\.filename), ["logo.png", "report.pdf"])

        let pdf = content.parts[1]
        XCTAssertEqual(pdf.attachmentID, "att-pdf")
        XCTAssertEqual(pdf.size, 2048)
        XCTAssertFalse(pdf.isInline)
        XCTAssertEqual(content.parts[0].contentID, "logo123")

        // Once the HTML references the inline image, it is no longer listed as a file.
        var referencing = content
        referencing.html = "<img src=\"cid:logo123\">"
        XCTAssertEqual(referencing.visibleAttachments.map(\.filename), ["report.pdf"])
    }

    func testUTF8BodyWithStaleLatin1Header() {
        // Gmail converts text parts to UTF-8 but leaves the original charset in the header.
        let part = MessagePart(
            partId: "0", mimeType: "text/plain", filename: "",
            headers: [header("Content-Type", "text/plain; charset=iso-8859-1")],
            body: MessagePartBody(size: 60, data: "VmllbGVuIERhbmsgZsO8ciBkaWUgc2NobmVsbGUgQmVhcmJlaXR1bmcg4oCTIGF1w59lcmRlbSBtw7ZjaHRlIGljaA")
        )
        let message = GmailMessage(id: "m1", threadId: "t1", payload: part)
        XCTAssertEqual(MessageContent(message: message).plainText, "Vielen Dank für die schnelle Bearbeitung – außerdem möchte ich")
    }

    func testHeaderAccessors() {
        let message = sampleMessage
        XCTAssertEqual(message.subject, "Quarterly report")
        XCTAssertEqual(message.from, EmailAddress(name: "Doe, Jane", address: "jane@example.com"))
        XCTAssertEqual(message.to.map(\.address), ["me@example.com", "bob@example.com"])
        XCTAssertEqual(message.date, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(message.isUnread)
        XCTAssertFalse(message.isStarred)
        XCTAssertEqual(ReplyBuilder.references(for: message), ["<m1@example.com>", "<m2@example.com>"])
    }

    func testThreadSummary() {
        let thread = GmailThread(id: "t1", historyId: nil, snippet: nil, messages: [sampleMessage])
        let summary = ThreadSummary(thread: thread, selfAddresses: ["me@example.com"])
        XCTAssertEqual(summary.subject, "Quarterly report")
        XCTAssertEqual(summary.participants, ["Doe, Jane"])
        XCTAssertEqual(summary.snippet, "Hallo & tschüss")
        XCTAssertTrue(summary.isUnread)
        XCTAssertTrue(summary.hasAttachments)
        XCTAssertEqual(summary.labelIDs, ["INBOX", "UNREAD"])
    }

    func testReplyRecipients() {
        let message = sampleMessage
        let own: Set<String> = ["ME@example.com"]

        let reply = ReplyBuilder.recipients(for: message, kind: .reply, selfAddresses: own)
        XCTAssertEqual(reply.to.map(\.address), ["jane@example.com"])
        XCTAssertTrue(reply.cc.isEmpty)

        let all = ReplyBuilder.recipients(for: message, kind: .replyAll, selfAddresses: own)
        XCTAssertEqual(all.to.map(\.address), ["jane@example.com", "bob@example.com"])
        XCTAssertEqual(all.cc.map(\.address), ["carol@example.com"])
    }

    func testReplySubjectAndQuote() {
        XCTAssertEqual(ReplyBuilder.subject(for: "Hello", kind: .reply), "Re: Hello")
        XCTAssertEqual(ReplyBuilder.subject(for: "RE: Hello", kind: .replyAll), "RE: Hello")
        XCTAssertEqual(ReplyBuilder.subject(for: "Hello", kind: .forward), "Fwd: Hello")

        let body = ReplyBuilder.body(for: sampleMessage, quotedText: "line1\n> older", kind: .reply, dateFormatter: { _ in "DATE" })
        XCTAssertEqual(body, "\n\nOn DATE, \"Doe, Jane\" <jane@example.com> wrote:\n> line1\n>> older\n")
    }

    func testGermanQuoteHeader() {
        let body = ReplyBuilder.body(for: sampleMessage, quotedText: "Hallo", kind: .reply, strings: .german, dateFormatter: { _ in "1. Okt." })
        XCTAssertEqual(body, "\n\nAm 1. Okt. schrieb \"Doe, Jane\" <jane@example.com>:\n> Hallo\n")

        let forward = ReplyBuilder.body(for: sampleMessage, quotedText: "Text", kind: .forward, strings: .german, dateFormatter: { _ in "D" })
        XCTAssertTrue(forward.contains("---------- Weitergeleitete Nachricht ---------\nVon: \"Doe, Jane\" <jane@example.com>\nDatum: D\nBetreff: Quarterly report"))
    }

    func testSentConversationUsesRecipientsAsCorrespondents() {
        let thread = GmailThread(id: "t1", historyId: nil, snippet: nil, messages: [sampleMessage])
        let sent = ThreadSummary(thread: thread, selfAddresses: ["jane@example.com"], selfName: "Ich")
        XCTAssertTrue(sent.isOnlyOwnMessages)
        XCTAssertEqual(sent.correspondents, ["me@example.com", "Bob", "carol@example.com"])

        let received = ThreadSummary(thread: thread, selfAddresses: ["me@example.com"])
        XCTAssertFalse(received.isOnlyOwnMessages)
        XCTAssertEqual(received.correspondents, ["Doe, Jane"])
    }

    func testOwnMessagesUseSelfName() {
        let thread = GmailThread(id: "t1", historyId: nil, snippet: nil, messages: [sampleMessage])
        let summary = ThreadSummary(thread: thread, selfAddresses: ["jane@example.com"], selfName: "Ich")
        XCTAssertEqual(summary.participants, ["Ich"])
    }
}
