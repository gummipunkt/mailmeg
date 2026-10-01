import AppKit
import AuthenticationServices
import MailmegKit

/// Runs Google's OAuth consent flow in the system's web authentication sheet.
@MainActor
final class AuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authorize(config: GoogleOAuthConfig, loginHint: String? = nil) async throws -> OAuthTokens {
        let pkce = PKCE()
        let state = UUID().uuidString
        let url = config.authorizationURL(pkce: pkce, state: state, loginHint: loginHint)

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: config.redirectScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? OAuthError.missingCode)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: OAuthError.authorizationFailed("The sign-in window could not be opened."))
            }
        }
        session = nil

        let code = try config.authorizationCode(from: callbackURL, expectedState: state)
        return try await GoogleOAuthClient(config: config).exchange(code: code, pkce: pkce)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }
}
