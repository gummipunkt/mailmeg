import XCTest
@testable import MailmegKit

final class ComposeTests: XCTestCase {
    func testSendAsDecodingAndSignature() throws {
        let json = #"{"sendAs":[{"sendAsEmail":"me@example.com","displayName":"Me","signature":"<div>Best,<br><b>Me</b></div>","isDefault":true,"isPrimary":true},{"sendAsEmail":"alias@example.com","verificationStatus":"pending"}]}"#
        struct Response: Decodable { let sendAs: [GmailSendAs] }
        let aliases = try JSONDecoder().decode(Response.self, from: Data(json.utf8)).sendAs
        XCTAssertEqual(aliases.count, 2)
        XCTAssertEqual(aliases[0].plainSignature, "Best,\nMe")
        XCTAssertTrue(aliases[0].isUsable)
        XCTAssertFalse(aliases[1].isUsable)
        XCTAssertEqual(aliases[1].plainSignature, "")
    }

    func testReplyToHeader() {
        let message = OutgoingMessage(
            from: EmailAddress(name: "Me", address: "alias@example.com"),
            replyTo: [EmailAddress(address: "replies@example.com")],
            to: [EmailAddress(address: "you@example.com")],
            subject: "x",
            textBody: "y"
        )
        let raw = String(decoding: MIMEBuilder().build(message), as: UTF8.self)
        XCTAssertTrue(raw.contains("From: Me <alias@example.com>\r\nReply-To: replies@example.com\r\n"))
    }

    func testPreferredSenderUsesAddressedAlias() {
        let message = GmailMessage(id: "m", threadId: "t", payload: MessagePart(headers: [
            MessageHeader(name: "From", value: "Bob <bob@example.com>"),
            MessageHeader(name: "To", value: "Work <ALIAS@example.com>"),
        ]))
        XCTAssertEqual(ReplyBuilder.preferredSender(for: message, ownAddresses: ["me@example.com", "alias@example.com"]), "alias@example.com")
        XCTAssertNil(ReplyBuilder.preferredSender(for: message, ownAddresses: ["me@example.com"]))
    }

    func testPreferredSenderUsesHeaderOrderNotAlphabet() {
        // Gmail puts the account's main address into Delivered-To; the alias in To must win.
        let message = GmailMessage(id: "m", threadId: "t", payload: MessagePart(headers: [
            MessageHeader(name: "From", value: "Kunde <kunde@example.org>"),
            MessageHeader(name: "To", value: "Service <service@wibros.de>"),
            MessageHeader(name: "Delivered-To", value: "alpha@gmail.com"),
        ]))
        XCTAssertEqual(ReplyBuilder.preferredSender(for: message, ownAddresses: ["alpha@gmail.com", "service@wibros.de"]), "service@wibros.de")
    }

    func testPreferredSenderFallsBackToDeliveryHeadersAndThread() {
        let bcc = GmailMessage(id: "m2", threadId: "t", payload: MessagePart(headers: [
            MessageHeader(name: "From", value: "list@example.org"),
            MessageHeader(name: "To", value: "list@example.org"),
            MessageHeader(name: "X-Original-To", value: "info@example.com"),
        ]))
        XCTAssertEqual(ReplyBuilder.preferredSender(for: bcc, ownAddresses: ["me@gmail.com", "info@example.com"]), "info@example.com")

        let mine = GmailMessage(id: "m1", threadId: "t", payload: MessagePart(headers: [
            MessageHeader(name: "From", value: "Me <shop@example.com>"),
            MessageHeader(name: "To", value: "kunde@example.org"),
        ]))
        let answer = GmailMessage(id: "m3", threadId: "t", payload: MessagePart(headers: [
            MessageHeader(name: "From", value: "kunde@example.org"),
            MessageHeader(name: "To", value: "undisclosed-recipients:;"),
        ]))
        XCTAssertEqual(ReplyBuilder.preferredSender(for: answer, in: [mine, answer], ownAddresses: ["me@gmail.com", "shop@example.com"]), "shop@example.com")
        XCTAssertEqual(ReplyBuilder.preferredSender(for: mine, ownAddresses: ["me@gmail.com", "shop@example.com"]), "shop@example.com")
    }

    func testQuoteBlock() {
        let message = GmailMessage(id: "m", threadId: "t", internalDate: "0", payload: MessagePart(headers: [
            MessageHeader(name: "From", value: "Bob <bob@example.com>"),
        ]))
        let block = ReplyBuilder.quote(for: message, quotedText: "Hi\nthere", kind: .reply, dateFormatter: { _ in "D" })
        XCTAssertEqual(block, "On D, Bob <bob@example.com> wrote:\n> Hi\n> there")
        XCTAssertEqual(ReplyBuilder.quote(for: message, quotedText: "x", kind: .new, dateFormatter: { _ in "" }), "")
    }

    func testHTMLRendersQuoteLinksAndSignature() {
        let text = "Thanks!\n\n-- \nBest,\nMe\n\nOn D, Bob wrote:\n> see https://example.com\n> ok"
        let html = ComposeHTML.render(text: text, signatureText: "-- \nBest,\nMe", signatureHTML: "<div>Best,<br><b>Me</b></div>")
        XCTAssertTrue(html.contains("Thanks!<br><br>"))
        XCTAssertTrue(html.contains("<div class=\"gmail_signature\"><div>Best,<br><b>Me</b></div></div>"))
        XCTAssertFalse(html.contains("-- "))
        XCTAssertTrue(html.contains("<blockquote"))
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">https://example.com</a><br>ok</blockquote>"))
    }

    func testHTMLWithoutSignatureEscapes() {
        let html = ComposeHTML.render(text: "a < b & c")
        XCTAssertTrue(html.contains("a &lt; b &amp; c"))
    }
}
