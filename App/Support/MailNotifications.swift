import AppKit
import Foundation
import MailmegKit
import UserNotifications

/// macOS notifications for new mail: banners (also while MailMeG is in front), a click
/// opens the conversation, and the actions Reply, Mark as Read and Archive work right
/// from the notification.
@MainActor
final class MailNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MailNotifications()

    static let newMailCategory = "NEW_MAIL"
    private enum Action {
        static let reply = "REPLY"
        static let markRead = "MARK_READ"
        static let archive = "ARCHIVE"
    }

    private weak var model: AppModel?

    /// Must run before the app finishes launching, so a click on a notification that
    /// started the app is delivered too.
    func configure(model: AppModel) {
        self.model = model
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reply = UNTextInputNotificationAction(
            identifier: Action.reply,
            title: tr("Antworten", "Reply"),
            options: [],
            textInputButtonTitle: tr("Senden", "Send"),
            textInputPlaceholder: tr("Antwort …", "Reply…")
        )
        let markRead = UNNotificationAction(identifier: Action.markRead, title: tr("Als gelesen markieren", "Mark as Read"))
        let archive = UNNotificationAction(identifier: Action.archive, title: tr("Archivieren", "Archive"))
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.newMailCategory, actions: [reply, markRead, archive], intentIdentifiers: [], options: []),
        ])
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Opens the notification settings of MailMeG in System Settings.
    func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? "de.mailmeg.app"
        let urls = [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    /// Posts a sample notification so people can check their settings.
    func sendTest() async {
        let content = UNMutableNotificationContent()
        content.title = "MailMeG"
        content.subtitle = tr("Test-Mitteilung", "Test notification")
        content.body = tr("So sehen Mitteilungen über neue E-Mails aus.", "This is how new email notifications look.")
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    /// Removes delivered notifications of a conversation once it has been read.
    func removeNotifications(threadID: String) {
        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
            let ids = notifications
                .filter { $0.request.content.userInfo["thread"] as? String == threadID }
                .map(\.request.identifier)
            if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let threadID = notification.request.content.userInfo["thread"] as? String
        let isOpen = await MainActor.run { NSApp.isActive && threadID != nil && self.model?.selectedThreadID == threadID }
        return isOpen ? [] : [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let accountID = info["account"] as? String, let threadID = info["thread"] as? String else { return }
        let action = response.actionIdentifier
        let text = (response as? UNTextInputNotificationResponse)?.userText
        await handle(action: action, accountID: accountID, threadID: threadID, text: text)
    }

    private func handle(action: String, accountID: String, threadID: String, text: String?) async {
        guard let model else { return }
        switch action {
        case Action.markRead:
            await model.notificationAction(.markRead, accountID: accountID, threadID: threadID)
        case Action.archive:
            await model.notificationAction(.archive, accountID: accountID, threadID: threadID)
        case Action.reply:
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            await model.replyFromNotification(text, accountID: accountID, threadID: threadID)
        default:
            model.openFromNotification(accountID: accountID, threadID: threadID)
        }
    }
}
