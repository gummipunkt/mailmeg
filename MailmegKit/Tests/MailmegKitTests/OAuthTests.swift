import XCTest
@testable import MailmegKit

final class MockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (Int, Data)
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
        let (status, data) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }

    var requestCount: Int { lock.withLock { requests.count } }
}

func body(of request: URLRequest) -> String {
    String(decoding: request.httpBody ?? Data(), as: UTF8.self)
}

final class OAuthTests: XCTestCase {
    let config = GoogleOAuthConfig(clientID: "1234-abc.apps.googleusercontent.com")

    func testRedirectSchemeIsReversedClientID() {
        XCTAssertEqual(config.redirectScheme, "com.googleusercontent.apps.1234-abc")
        XCTAssertEqual(config.redirectURI, "com.googleusercontent.apps.1234-abc:/oauth2redirect")
        XCTAssertTrue(config.isValid)
        XCTAssertFalse(GoogleOAuthConfig(clientID: "nonsense").isValid)
    }

    func testAuthorizationURLContainsPKCE() throws {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = config.authorizationURL(pkce: pkce, state: "xyz")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        XCTAssertEqual(value("code_challenge"), pkce.challenge)
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("redirect_uri"), config.redirectURI)
        XCTAssertEqual(value("state"), "xyz")
        XCTAssertEqual(value("scope"), "https://www.googleapis.com/auth/gmail.modify")
    }

    func testAuthorizationCodeValidatesState() throws {
        let callback = URL(string: "com.googleusercontent.apps.1234-abc:/oauth2redirect?state=xyz&code=4/abc")!
        XCTAssertEqual(try config.authorizationCode(from: callback, expectedState: "xyz"), "4/abc")
        XCTAssertThrowsError(try config.authorizationCode(from: callback, expectedState: "other")) { error in
            XCTAssertEqual(error as? OAuthError, .stateMismatch)
        }
        let denied = URL(string: "com.googleusercontent.apps.1234-abc:/oauth2redirect?error=access_denied&state=xyz")!
        XCTAssertThrowsError(try config.authorizationCode(from: denied, expectedState: "xyz")) { error in
            XCTAssertEqual(error as? OAuthError, .authorizationFailed("access_denied"))
        }
    }

    func testCodeExchange() async throws {
        let transport = MockTransport([{ request in
            XCTAssertEqual(request.url, GoogleOAuthConfig.tokenEndpoint)
            let form = body(of: request)
            XCTAssertTrue(form.contains("grant_type=authorization_code"))
            XCTAssertTrue(form.contains("code_verifier=verifier"))
            XCTAssertTrue(form.contains("code=the-code"))
            return (200, Data(#"{"access_token":"at","expires_in":3600,"refresh_token":"rt","scope":"s"}"#.utf8))
        }])
        let now = Date(timeIntervalSince1970: 1000)
        let client = GoogleOAuthClient(config: config, transport: transport, now: { now })
        let tokens = try await client.exchange(code: "the-code", pkce: PKCE(verifier: "verifier"))
        XCTAssertEqual(tokens, OAuthTokens(accessToken: "at", refreshToken: "rt", expiresAt: now.addingTimeInterval(3600), scope: "s"))
    }

    func testRefreshKeepsRefreshToken() async throws {
        let transport = MockTransport([{ _ in (200, Data(#"{"access_token":"new","expires_in":10}"#.utf8)) }])
        let client = GoogleOAuthClient(config: config, transport: transport)
        let tokens = try await client.refresh(refreshToken: "rt")
        XCTAssertEqual(tokens.accessToken, "new")
        XCTAssertEqual(tokens.refreshToken, "rt")
    }

    func testInvalidGrantIsReported() async {
        let transport = MockTransport([{ _ in (400, Data(#"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#.utf8)) }])
        let client = GoogleOAuthClient(config: config, transport: transport)
        do {
            _ = try await client.refresh(refreshToken: "rt")
            XCTFail("Expected error")
        } catch {
            XCTAssertEqual(error as? OAuthError, .invalidGrant)
        }
    }

    func testTokenManagerRefreshesOnlyWhenExpired() async throws {
        let transport = MockTransport([{ _ in (200, Data(#"{"access_token":"fresh","expires_in":3600}"#.utf8)) }])
        let client = GoogleOAuthClient(config: config, transport: transport)
        let valid = OAuthTokens(accessToken: "valid", refreshToken: "rt", expiresAt: Date().addingTimeInterval(3600))
        let manager = TokenManager(tokens: valid, oauth: client, onUpdate: { _ in })
        let first = try await manager.accessToken()
        XCTAssertEqual(first, "valid")
        XCTAssertEqual(transport.requestCount, 0)

        let expired = OAuthTokens(accessToken: "old", refreshToken: "rt", expiresAt: Date().addingTimeInterval(-10))
        let updated = Box()
        let expiredManager = TokenManager(tokens: expired, oauth: client, onUpdate: { updated.set($0.accessToken) })
        async let a = expiredManager.accessToken()
        async let b = expiredManager.accessToken()
        let results = try await [a, b]
        XCTAssertEqual(results, ["fresh", "fresh"])
        XCTAssertEqual(transport.requestCount, 1, "Concurrent callers must share one refresh")
        XCTAssertEqual(updated.value, "fresh")
    }
}

final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    var value: String? { lock.withLock { stored } }
    func set(_ value: String) { lock.withLock { stored = value } }
}
