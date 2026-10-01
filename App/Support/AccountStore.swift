import Foundation
import MailmegKit

/// Persists the list of signed-in accounts (UserDefaults) and their tokens (Keychain).
enum AccountStore {
    private static let accountsKey = "accounts"

    static var emails: [String] {
        get { UserDefaults.standard.stringArray(forKey: accountsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: accountsKey) }
    }

    static func tokens(for email: String) -> OAuthTokens? {
        guard let data = Keychain.data(account: email) else { return nil }
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    static func save(_ tokens: OAuthTokens, for email: String) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        try? Keychain.set(data, account: email)
    }

    static func add(_ email: String, tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try Keychain.set(data, account: email)
        if !emails.contains(email) {
            emails.append(email)
        }
    }

    static func remove(_ email: String) {
        Keychain.delete(account: email)
        emails.removeAll { $0 == email }
    }
}
