import XCTest
@testable import MailmegKit

final class GmailClientTests: XCTestCase {
    private func makeClient(api: MockTransport, oauth: MockTransport = MockTransport([{ _ in (200, Data(#"{"access_token":"refreshed","expires_in":3600}"#.utf8)) }])) -> GmailClient {
        let config = GoogleOAuthConfig(clientID: "1234-abc.apps.googleusercontent.com")
        let tokens = TokenManager(
            tokens: OAuthTokens(accessToken: "initial", refreshToken: "rt", expiresAt: Date().addingTimeInterval(3600)),
            oauth: GoogleOAuthClient(config: config, transport: oauth),
            onUpdate: { _ in }
        )
        return GmailClient(tokens: tokens, transport: api, sleep: { _ in })
    }

    func testListThreadsBuildsQuery() async throws {
        let api = MockTransport([{ request in
            let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(components.path, "/gmail/v1/users/me/threads")
            let items = components.queryItems ?? []
            XCTAssertEqual(items.filter { $0.name == "labelIds" }.map(\.value), ["INBOX"])
            XCTAssertEqual(items.first { $0.name == "q" }?.value, "from:bob has:attachment")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer initial")
            return (200, Data(#"{"threads":[{"id":"t1","snippet":"hi","historyId":"5"}],"nextPageToken":"p2"}"#.utf8))
        }])
        let list = try await makeClient(api: api).listThreads(labelIDs: ["INBOX"], query: "from:bob has:attachment")
        XCTAssertEqual(list.threads?.map(\.id), ["t1"])
        XCTAssertEqual(list.nextPageToken, "p2")
    }

    func testRetriesWithRefreshedTokenAfter401() async throws {
        let api = MockTransport([
            { _ in (401, Data(#"{"error":{"code":401,"message":"Invalid Credentials"}}"#.utf8)) },
            { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer refreshed")
                return (200, Data(#"{"labels":[{"id":"INBOX","name":"INBOX","type":"system"}]}"#.utf8))
            },
        ])
        let labels = try await makeClient(api: api).labels()
        XCTAssertEqual(labels.map(\.id), ["INBOX"])
        XCTAssertEqual(api.requestCount, 2)
    }

    func testRetriesRateLimitedRequests() async throws {
        let api = MockTransport([
            { _ in (429, Data(#"{"error":{"code":429,"message":"Too many requests","errors":[{"reason":"rateLimitExceeded"}]}}"#.utf8)) },
            { _ in (503, Data()) },
            { _ in (200, Data(#"{"emailAddress":"me@example.com","historyId":"42"}"#.utf8)) },
        ])
        let profile = try await makeClient(api: api).profile()
        XCTAssertEqual(profile.emailAddress, "me@example.com")
        XCTAssertEqual(api.requestCount, 3)
    }

    func testDoesNotRetryClientErrors() async {
        let api = MockTransport([{ _ in (400, Data(#"{"error":{"code":400,"message":"Invalid query","errors":[{"reason":"invalidArgument"}]}}"#.utf8)) }])
        do {
            _ = try await makeClient(api: api).listThreads(query: "(")
            XCTFail("Expected error")
        } catch let error as GmailAPIError {
            XCTAssertEqual(error.status, 400)
            XCTAssertEqual(error.message, "Invalid query")
            XCTAssertEqual(api.requestCount, 1)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    func testThreadsPreserveOrderAndSkipMissing() async throws {
        let api = MockTransport([{ request in
            let id = request.url!.lastPathComponent
            if id == "gone" { return (404, Data(#"{"error":{"code":404,"message":"Not Found"}}"#.utf8)) }
            return (200, Data(#"{"id":"\#(id)","messages":[]}"#.utf8))
        }])
        let ids = (0..<20).map { "t\($0)" } + ["gone"]
        let threads = try await makeClient(api: api).threads(ids: ids, concurrency: 4)
        XCTAssertEqual(threads.map(\.id), (0..<20).map { "t\($0)" })
    }

    func testSendUsesMultipartUpload() async throws {
        let api = MockTransport([{ request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://gmail.googleapis.com/upload/gmail/v1/users/me/messages/send?uploadType=multipart")
            let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
            XCTAssertTrue(contentType.hasPrefix("multipart/related; boundary="))
            let payload = body(of: request)
            XCTAssertTrue(payload.contains(#"{"threadId":"t9"}"#))
            XCTAssertTrue(payload.contains("Content-Type: message/rfc822\r\n\r\nSubject: Hi"))
            return (200, Data(#"{"id":"m1","threadId":"t9","labelIds":["SENT"]}"#.utf8))
        }])
        let sent = try await makeClient(api: api).send(rfc822: Data("Subject: Hi\r\n\r\nBody".utf8), threadID: "t9")
        XCTAssertEqual(sent.id, "m1")
    }
}
