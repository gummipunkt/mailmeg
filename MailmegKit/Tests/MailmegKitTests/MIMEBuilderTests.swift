import XCTest
@testable import MailmegKit

final class MIMEBuilderTests: XCTestCase {
    private func builder() -> MIMEBuilder {
        var counter = 0
        return MIMEBuilder(
            makeBoundary: { counter += 1; return "B\(counter)" },
            now: { Date(timeIntervalSince1970: 0) }
        )
    }

    func testSimplePlainTextMessage() {
        let message = OutgoingMessage(
            from: EmailAddress(name: "Me", address: "me@example.com"),
            to: [EmailAddress(address: "you@example.com")],
            subject: "Hello",
            textBody: "Hello\nWorld"
        )
        let raw = String(decoding: builder().build(message), as: UTF8.self)
        XCTAssertTrue(raw.hasPrefix("From: Me <me@example.com>\r\nTo: you@example.com\r\nSubject: Hello\r\nDate: "))
        XCTAssertTrue(raw.contains("MIME-Version: 1.0\r\nContent-Type: text/plain; charset=\"UTF-8\"\r\nContent-Transfer-Encoding: base64\r\n\r\nSGVsbG8NCldvcmxk"))
        XCTAssertFalse(raw.contains("multipart"))
    }

    func testNonASCIISubjectAndNameAreEncoded() {
        let message = OutgoingMessage(
            to: [EmailAddress(name: "Jürgen", address: "j@example.com")],
            subject: "Grüße",
            textBody: ""
        )
        let raw = String(decoding: builder().build(message), as: UTF8.self)
        XCTAssertTrue(raw.contains("Subject: =?UTF-8?B?R3LDvMOfZQ==?=\r\n"))
        XCTAssertTrue(raw.contains("To: =?UTF-8?B?SsO8cmdlbg==?= <j@example.com>\r\n"))
    }

    func testLongSubjectIsSplitIntoShortEncodedWords() {
        let subject = String(repeating: "ä", count: 60)
        let encoded = MIMEBuilder.encodeHeaderText(subject)
        let words = encoded.components(separatedBy: "\r\n ")
        XCTAssertGreaterThan(words.count, 1)
        for word in words {
            XCTAssertLessThanOrEqual(word.count, 75)
            XCTAssertTrue(word.hasPrefix("=?UTF-8?B?") && word.hasSuffix("?="))
        }
    }

    func testReplyHeadersAndAttachment() {
        let message = OutgoingMessage(
            to: [EmailAddress(address: "you@example.com")],
            cc: [EmailAddress(name: "Doe, Jane", address: "jane@example.com")],
            subject: "Re: Report",
            textBody: "See attached.",
            inReplyTo: "<abc@mail.example.com>",
            references: ["<root@mail.example.com>", "<abc@mail.example.com>"],
            attachments: [OutgoingAttachment(filename: "Übersicht.png", mimeType: "image/png", data: Data("PNGDATA".utf8))]
        )
        let raw = String(decoding: builder().build(message), as: UTF8.self)
        XCTAssertTrue(raw.contains("Cc: \"Doe, Jane\" <jane@example.com>\r\n"))
        XCTAssertTrue(raw.contains("In-Reply-To: <abc@mail.example.com>\r\n"))
        XCTAssertTrue(raw.contains("References: <root@mail.example.com> <abc@mail.example.com>\r\n"))
        XCTAssertTrue(raw.contains("Content-Type: multipart/mixed; boundary=\"B1\"\r\n\r\n--B1\r\nContent-Type: text/plain"))
        XCTAssertTrue(raw.contains("Content-Disposition: attachment; filename*=UTF-8''%C3%9Cbersicht.png\r\n"))
        XCTAssertTrue(raw.contains("UE5HREFUQQ=="))
        XCTAssertTrue(raw.hasSuffix("--B1--"))
    }

    func testHTMLAlternative() {
        let message = OutgoingMessage(to: [EmailAddress(address: "a@example.com")], subject: "x", textBody: "plain", htmlBody: "<p>rich</p>")
        let raw = String(decoding: builder().build(message), as: UTF8.self)
        XCTAssertTrue(raw.contains("Content-Type: multipart/alternative; boundary=\"B1\""))
        XCTAssertTrue(raw.contains("Content-Type: text/html; charset=\"UTF-8\""))
    }
}
