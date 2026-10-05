import XCTest
@testable import MailmegKit

/// Like `MockTransport`, but handlers can also set response headers.
private final class HeaderMockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (Int, [String: String], Data)
    private let lock = NSLock()
    private var handlers: [Handler]
    private(set) var requests: [URLRequest] = []

    init(_ handlers: [Handler]) {
        self.handlers = handlers
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let handler: Handler = lock.withLock {
            requests.append(request)
            return handlers.count > 1 ? handlers.removeFirst() : handlers[0]
        }
        let (status, headers, data) = try handler(request)
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}

final class DriveTests: XCTestCase {
    private func makeClient(_ api: HeaderMockTransport) -> DriveClient {
        let config = GoogleOAuthConfig(clientID: "1234-abc.apps.googleusercontent.com")
        let tokens = TokenManager(
            tokens: OAuthTokens(accessToken: "token", refreshToken: "rt", expiresAt: Date().addingTimeInterval(3600)),
            oauth: GoogleOAuthClient(config: config, transport: MockTransport([{ _ in (500, Data()) }])),
            onUpdate: { _ in }
        )
        return DriveClient(api: GmailClient(tokens: tokens, transport: api, sleep: { _ in }))
    }

    func testResumableUploadInChunks() async throws {
        let chunk = 256 * 1024
        let data = Data(repeating: 7, count: chunk + 1000)
        let session = "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&upload_id=abc"
        let api = HeaderMockTransport([
            { request in
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertTrue(request.url!.absoluteString.hasPrefix("https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable"))
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Upload-Content-Length"), String(chunk + 1000))
                XCTAssertEqual(request.value(forHTTPHeaderField: "X-Upload-Content-Type"), "application/zip")
                let json = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
                XCTAssertEqual(json?["name"] as? String, "Unterlagen.zip")
                XCTAssertEqual(json?["parents"] as? [String], ["folder-1"])
                return (200, ["Location": session], Data())
            },
            { request in
                XCTAssertEqual(request.url!.absoluteString, session)
                XCTAssertEqual(request.httpMethod, "PUT")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Range"), "bytes 0-\(chunk - 1)/\(chunk + 1000)")
                XCTAssertEqual(request.httpBody?.count, chunk)
                return (308, ["Range": "bytes=0-\(chunk - 1)"], Data())
            },
            { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Range"), "bytes \(chunk)-\(chunk + 999)/\(chunk + 1000)")
                XCTAssertEqual(request.httpBody?.count, 1000)
                return (200, [:], Data(#"{"id":"f1","name":"Unterlagen.zip","size":"263144","webViewLink":"https://drive.google.com/file/d/f1/view"}"#.utf8))
            },
        ])
        let steps = ProgressRecorder()
        let file = try await makeClient(api).upload(
            data: data, name: "Unterlagen.zip", mimeType: "application/zip", parentID: "folder-1", chunkSize: chunk,
            progress: { steps.add($0) }
        )
        XCTAssertEqual(file.id, "f1")
        XCTAssertEqual(file.link, "https://drive.google.com/file/d/f1/view")
        XCTAssertEqual(file.byteCount, 263_144)
        XCTAssertEqual(api.requests.count, 3)
        XCTAssertEqual(steps.values.first, 0)
        XCTAssertEqual(steps.values.last, 1)
    }

    func testShareFallsBackToInvitationEmail() async throws {
        let api = HeaderMockTransport([
            { request in
                XCTAssertTrue(request.url!.absoluteString.hasSuffix("/drive/v3/files/f1/permissions?sendNotificationEmail=false"))
                let json = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
                XCTAssertEqual(json?["type"], "user")
                XCTAssertEqual(json?["emailAddress"], "anna@example.org")
                return (400, [:], Data(#"{"error":{"code":400,"message":"Bad Request. User message: \"Sharing requires a notification\"","errors":[{"reason":"invalidSharingRequest"}]}}"#.utf8))
            },
            { request in
                XCTAssertTrue(request.url!.absoluteString.hasSuffix("sendNotificationEmail=true"))
                return (200, [:], Data(#"{"id":"p1"}"#.utf8))
            },
            { request in
                let json = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
                XCTAssertEqual(json?["type"], "anyone")
                XCTAssertEqual(json?["role"], "reader")
                return (200, [:], Data(#"{"id":"p2"}"#.utf8))
            },
        ])
        let client = makeClient(api)
        try await client.share(fileID: "f1", with: ["anna@example.org"])
        try await client.shareWithAnyone(fileID: "f1")
        XCTAssertEqual(api.requests.count, 3)
    }

    func testScope() {
        XCTAssertTrue(DriveClient.isGranted(scope: "https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/drive.file"))
        XCTAssertFalse(DriveClient.isGranted(scope: "https://www.googleapis.com/auth/gmail.modify"))
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Double] = []
    func add(_ value: Double) { lock.withLock { recorded.append(value) } }
    var values: [Double] { lock.withLock { recorded } }
}
