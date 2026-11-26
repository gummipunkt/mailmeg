import Foundation
import MailmegKit

enum AppSettings {
    static let clientIDKey = "googleClientID"
    /// The colours of the window's backdrop (`ColorMood`).
    static let colorMoodKey = "colorMood"
    /// How strong the backdrop's colours are (1 = as designed).
    static let colorIntensityKey = "colorIntensity"
    /// How opaque the sheets on the backdrop are (list, conversation, calendar).
    static let sheetOpacityKey = "sheetOpacity"
    /// How much of the desktop shows through the window's backdrop (0 = nothing).
    static let backdropTransparencyKey = "backdropTransparency"
    static let swipeLeftKey = "swipeLeftAction"
    static let swipeRightKey = "swipeRightAction"
    /// ⌘← and ⌘→ in the message list act like swiping to the left and right.
    static let arrowKeyActionsKey = "arrowKeyActions"

    /// What swiping a conversation in the list does.
    enum SwipeAction: String, CaseIterable, Identifiable {
        case none, archive, trash, toggleRead, toggleStar, spam

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return tr("Nichts", "Nothing")
            case .archive: return tr("Archivieren", "Archive")
            case .trash: return tr("Löschen", "Delete")
            case .toggleRead: return tr("Gelesen/Ungelesen", "Read/Unread")
            case .toggleStar: return tr("Markieren", "Star")
            case .spam: return tr("Als Spam melden", "Report Spam")
            }
        }
    }
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
    static let dockBadgeKey = "dockBadge"
    static let collapseQuotesKey = "collapseQuotes"
    static let replyInWindowKey = "replyInWindow"
    static let faviconAvatarsKey = "faviconAvatars"
    static let newestFirstKey = "conversationNewestFirst"

    /// Quoted earlier messages start collapsed (default) or shown.
    static var collapseQuotes: Bool {
        UserDefaults.standard.object(forKey: collapseQuotesKey) as? Bool ?? true
    }

    /// Replies open in their own window instead of below the conversation (default).
    static var replyInWindow: Bool {
        UserDefaults.standard.bool(forKey: replyInWindowKey)
    }

    /// Senders are shown with their domain's website icon where there is one.
    static var faviconAvatars: Bool {
        UserDefaults.standard.object(forKey: faviconAvatarsKey) as? Bool ?? true
    }

    /// Shows the number of unread conversations on the Dock icon.
    static var dockBadgeEnabled: Bool {
        UserDefaults.standard.object(forKey: dockBadgeKey) as? Bool ?? true
    }

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
