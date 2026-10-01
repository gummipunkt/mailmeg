import Foundation

/// Configuration of a Google OAuth client of type "iOS" (also used for macOS apps).
///
/// Such clients use the reversed client ID as custom URL scheme for the redirect and
/// do not need a client secret; PKCE protects the authorization code.
public struct GoogleOAuthConfig: Sendable, Equatable {
    public static let defaultScopes = [
        "https://www.googleapis.com/auth/gmail.modify",
    ]

    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public static let revocationEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!

    public var clientID: String
    public var clientSecret: String?
    public var scopes: [String]

    public init(clientID: String, clientSecret: String? = nil, scopes: [String] = GoogleOAuthConfig.defaultScopes) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientSecret = clientSecret
        self.scopes = scopes
    }

    /// `1234-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.1234-abc`
    public var redirectScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    public var redirectURI: String {
        "\(redirectScheme):/oauth2redirect"
    }

    public var isValid: Bool {
        clientID.hasSuffix(".apps.googleusercontent.com") && clientID.count > ".apps.googleusercontent.com".count
    }

    public func authorizationURL(pkce: PKCE, state: String, loginHint: String? = nil) -> URL {
        var components = URLComponents(url: Self.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        if let loginHint {
            items.append(URLQueryItem(name: "login_hint", value: loginHint))
        }
        components.queryItems = items
        return components.url!
    }

    /// Extracts the authorization code from the redirect URL and validates the `state`.
    public func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw OAuthError.authorizationFailed(error)
        }
        guard value("state") == expectedState else {
            throw OAuthError.stateMismatch
        }
        guard let code = value("code"), !code.isEmpty else {
            throw OAuthError.missingCode
        }
        return code
    }
}

public struct OAuthTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var scope: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, scope: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    public func isExpired(at date: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        expiresAt.timeIntervalSince(date) < leeway
    }
}

public enum OAuthError: Error, LocalizedError, Equatable {
    case authorizationFailed(String)
    case stateMismatch
    case missingCode
    case missingRefreshToken
    /// The refresh token was revoked or expired; the user has to sign in again.
    case invalidGrant
    case tokenEndpoint(status: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .authorizationFailed(let reason): "Google sign-in failed: \(reason)"
        case .stateMismatch: "Google sign-in failed: state mismatch."
        case .missingCode: "Google sign-in failed: no authorization code was returned."
        case .missingRefreshToken: "Google did not return a refresh token. Remove the app's access at myaccount.google.com/permissions and sign in again."
        case .invalidGrant: "The Google session expired or was revoked. Please sign in again."
        case .tokenEndpoint(let status, let message): "Token request failed (\(status)): \(message)"
        }
    }
}

/// Talks to Google's OAuth token endpoint.
public struct GoogleOAuthClient: Sendable {
    public let config: GoogleOAuthConfig
    let transport: HTTPTransport
    let now: @Sendable () -> Date

    public init(config: GoogleOAuthConfig, transport: HTTPTransport = URLSessionTransport(), now: @escaping @Sendable () -> Date = Date.init) {
        self.config = config
        self.transport = transport
        self.now = now
    }

    public func exchange(code: String, pkce: PKCE) async throws -> OAuthTokens {
        var parameters = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("code_verifier", pkce.verifier),
            ("redirect_uri", config.redirectURI),
            ("client_id", config.clientID),
        ]
        if let secret = config.clientSecret { parameters.append(("client_secret", secret)) }
        let response = try await tokenRequest(parameters)
        guard let refreshToken = response.refresh_token else {
            throw OAuthError.missingRefreshToken
        }
        return OAuthTokens(
            accessToken: response.access_token,
            refreshToken: refreshToken,
            expiresAt: now().addingTimeInterval(TimeInterval(response.expires_in ?? 3600)),
            scope: response.scope
        )
    }

    public func refresh(refreshToken: String) async throws -> OAuthTokens {
        var parameters = [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", config.clientID),
        ]
        if let secret = config.clientSecret { parameters.append(("client_secret", secret)) }
        let response = try await tokenRequest(parameters)
        return OAuthTokens(
            accessToken: response.access_token,
            refreshToken: response.refresh_token ?? refreshToken,
            expiresAt: now().addingTimeInterval(TimeInterval(response.expires_in ?? 3600)),
            scope: response.scope
        )
    }

    public func revoke(token: String) async throws {
        var request = URLRequest(url: GoogleOAuthConfig.revocationEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoding.encode([("token", token)])
        _ = try await transport.data(for: request)
    }

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int?
        let refresh_token: String?
        let scope: String?
    }

    private struct TokenErrorResponse: Decodable {
        let error: String
        let error_description: String?
    }

    private func tokenRequest(_ parameters: [(String, String)]) async throws -> TokenResponse {
        var request = URLRequest(url: GoogleOAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoding.encode(parameters)

        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            let error = try? JSONDecoder().decode(TokenErrorResponse.self, from: data)
            if error?.error == "invalid_grant" {
                throw OAuthError.invalidGrant
            }
            let message = error.map { $0.error_description ?? $0.error } ?? String(decoding: data, as: UTF8.self)
            throw OAuthError.tokenEndpoint(status: response.statusCode, message: message)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}

/// Hands out valid access tokens and refreshes them when needed.
/// Concurrent callers share a single in-flight refresh.
public actor TokenManager {
    private var tokens: OAuthTokens
    private let oauth: GoogleOAuthClient
    private let onUpdate: @Sendable (OAuthTokens) -> Void
    private var refreshTask: Task<OAuthTokens, Error>?

    public init(tokens: OAuthTokens, oauth: GoogleOAuthClient, onUpdate: @escaping @Sendable (OAuthTokens) -> Void) {
        self.tokens = tokens
        self.oauth = oauth
        self.onUpdate = onUpdate
    }

    public var currentTokens: OAuthTokens { tokens }

    public func accessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, !tokens.isExpired() {
            return tokens.accessToken
        }
        if let refreshTask {
            return try await refreshTask.value.accessToken
        }
        let oauth = self.oauth
        let refreshToken = tokens.refreshToken
        let task = Task { try await oauth.refresh(refreshToken: refreshToken) }
        refreshTask = task
        do {
            let newTokens = try await task.value
            refreshTask = nil
            tokens = newTokens
            onUpdate(newTokens)
            return newTokens.accessToken
        } catch {
            refreshTask = nil
            throw error
        }
    }
}
