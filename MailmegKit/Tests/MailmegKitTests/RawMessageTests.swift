import XCTest
@testable import MailmegKit

final class RawMessageTests: XCTestCase {
    func testHeadersAreUnfoldedAndDecoded() {
        let source = "Delivered-To: alex@example.com\r\nReceived: from mail.example.com\r\n\tby mx.google.com; Wed, 1 Oct 2026\r\nSubject: =?UTF-8?B?R3LDvMOfZQ==?= =?UTF-8?Q?_aus_K=C3=B6ln?=\r\nFrom: Anna <anna@example.com>\r\n\r\nBody: not a header\r\n"
        let headers = RawMessage.headers(from: source)
        XCTAssertEqual(headers.map(\.name), ["Delivered-To", "Received", "Subject", "From"])
        XCTAssertEqual(headers[1].value, "from mail.example.com by mx.google.com; Wed, 1 Oct 2026")
        XCTAssertEqual(headers[2].value, "Grüße aus Köln")
    }

    func testPlainTextIsUnchanged() {
        XCTAssertEqual(RawMessage.decodeEncodedWords("Hello = world"), "Hello = world")
    }

    func testRawMessageRequest() async throws {
        let raw = Base64URL.encode(Data("Subject: Hi\r\n\r\nBody".utf8))
        let api = MockTransport([{ request in
            XCTAssertTrue(request.url!.absoluteString.contains("messages/m1?format=raw"))
            return (200, Data(#"{"id":"m1","raw":"\#(raw)"}"#.utf8))
        }])
        let config = GoogleOAuthConfig(clientID: "1234-abc.apps.googleusercontent.com")
        let tokens = TokenManager(
            tokens: OAuthTokens(accessToken: "a", refreshToken: "r", expiresAt: Date().addingTimeInterval(3600)),
            oauth: GoogleOAuthClient(config: config, transport: api),
            onUpdate: { _ in }
        )
        let data = try await GmailClient(tokens: tokens, transport: api).rawMessage(id: "m1")
        XCTAssertEqual(RawMessage.text(from: data), "Subject: Hi\r\n\r\nBody")
    }
}
