import Foundation
import MailmegKit

enum AppSettings {
    static let clientIDKey = "googleClientID"
    static let loadRemoteContentKey = "loadRemoteContent"
    static let notificationsKey = "notificationsEnabled"
    static let refreshIntervalKey = "refreshInterval"
    static let replyPositionKey = "replyPosition"
    static let signatureEnabledKey = "signatureEnabled"
    static let signatureInRepliesKey = "signatureInReplies"

    enum ReplyPosition: String, CaseIterable {
        /// Write above the quoted message (Gmail's default).
        case above
        /// Write below the quoted message (classic "bottom posting").
        case below
    }

    static var replyPosition: ReplyPosition {
        ReplyPosition(rawValue: UserDefaults.standard.string(forKey: replyPositionKey) ?? "") ?? .above
    }

    static var signatureEnabled: Bool {
        UserDefaults.standard.object(forKey: signatureEnabledKey) as? Bool ?? true
    }

    static var signatureInReplies: Bool {
        UserDefaults.standard.object(forKey: signatureInRepliesKey) as? Bool ?? true
    }

    static func defaultSenderKey(for accountID: String) -> String { "defaultSender.\(accountID)" }

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
