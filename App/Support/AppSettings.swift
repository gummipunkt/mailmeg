import Foundation
import MailmegKit

enum AppSettings {
    static let clientIDKey = "googleClientID"
    static let loadRemoteContentKey = "loadRemoteContent"
    static let notificationsKey = "notificationsEnabled"
    static let refreshIntervalKey = "refreshInterval"

    /// The OAuth client ID entered in the app, falling back to the one baked into Info.plist.
    static var clientID: String {
        get {
            if let stored = UserDefaults.standard.string(forKey: clientIDKey), !stored.isEmpty {
                return stored
            }
            let bundled = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String ?? ""
            return bundled.hasPrefix("$(") ? "" : bundled
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: clientIDKey)
        }
    }

    static var oauthConfig: GoogleOAuthConfig {
        GoogleOAuthConfig(clientID: clientID)
    }

    static var notificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: notificationsKey) as? Bool ?? true
    }

    static var refreshInterval: TimeInterval {
        let value = UserDefaults.standard.double(forKey: refreshIntervalKey)
        return value >= 15 ? value : 60
    }
}
