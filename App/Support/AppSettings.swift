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

    /// Seconds between automatic checks for new mail; 0 means "manually only".
    static var refreshInterval: TimeInterval {
        guard UserDefaults.standard.object(forKey: refreshIntervalKey) != nil else { return 60 }
        let value = UserDefaults.standard.double(forKey: refreshIntervalKey)
        return value <= 0 ? 0 : max(value, 15)
    }

    struct RefreshOption: Identifiable {
        let seconds: Double
        let title: String
        var id: Double { seconds }
    }

    static let showAvatarsKey = "showAvatars"

    static let refreshOptions: [RefreshOption] = [
        RefreshOption(seconds: 30, title: tr("Alle 30 Sekunden", "Every 30 seconds")),
        RefreshOption(seconds: 60, title: tr("Jede Minute", "Every minute")),
        RefreshOption(seconds: 120, title: tr("Alle 2 Minuten", "Every 2 minutes")),
        RefreshOption(seconds: 300, title: tr("Alle 5 Minuten", "Every 5 minutes")),
        RefreshOption(seconds: 600, title: tr("Alle 10 Minuten", "Every 10 minutes")),
        RefreshOption(seconds: 900, title: tr("Alle 15 Minuten", "Every 15 minutes")),
        RefreshOption(seconds: 1800, title: tr("Alle 30 Minuten", "Every 30 minutes")),
        RefreshOption(seconds: 3600, title: tr("Jede Stunde", "Every hour")),
        RefreshOption(seconds: 0, title: tr("Manuell", "Manually")),
    ]
}
