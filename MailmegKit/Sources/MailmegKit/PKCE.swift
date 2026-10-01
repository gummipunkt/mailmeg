import CryptoKit
import Foundation

/// Proof Key for Code Exchange (RFC 7636) with the S256 method.
public struct PKCE: Sendable, Equatable {
    public let verifier: String
    public let challenge: String

    public init() {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        self.init(verifier: Base64URL.encode(Data(bytes)))
    }

    public init(verifier: String) {
        self.verifier = verifier
        let digest = SHA256.hash(data: Data(verifier.utf8))
        self.challenge = Base64URL.encode(Data(digest))
    }
}
