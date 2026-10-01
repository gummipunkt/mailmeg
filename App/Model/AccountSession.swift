import Foundation
import MailmegKit
import Observation
import UserNotifications

struct SidebarItem: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
    let unread: Int
    let indent: Int
    /// Gmail label colour as hex string (user labels only).
    var colorHex: String? = nil
}

/// One signed-in Gmail account with its API client and labels.
@MainActor
@Observable
final class AccountSession: Identifiable {
    static let allMailID = "__ALL_MAIL__"

    let email: String
    nonisolated var id: String { email }
    var displayName: String?
    let client: GmailClient
    private let tokenManager: TokenManager

    var labels: [GmailLabel] = []
    var needsReauth = false
    private var lastHistoryID: String?

    /// List entries by thread ID, together with the thread's historyId. Gmail changes a
    /// thread's historyId whenever it changes, so unchanged threads are never fetched twice.
    private var summaryCache: [String: (historyID: String?, summary: ThreadSummary)] = [:]
    private var pendingCountIDs = Set<String>()
    private var countsTask: Task<Void, Never>?
    /// After Google reports an exhausted quota, background work pauses until this date.
    private(set) var rateLimitedUntil: Date?

    init(email: String, tokens: OAuthTokens, config: GoogleOAuthConfig, transport: HTTPTransport = URLSessionTransport(), persistsTokens: Bool = true) {
        self.email = email
        let oauth = GoogleOAuthClient(config: config, transport: transport)
        tokenManager = TokenManager(tokens: tokens, oauth: oauth) { updated in
            if persistsTokens {
                AccountStore.save(updated, for: email)
            }
        }
        client = GmailClient(tokens: tokenManager, transport: transport)
    }

    var sender: EmailAddress { EmailAddress(name: displayName, address: email) }

    var inboxUnread: Int {
        labels.first { $0.id == SystemLabel.inbox }?.threadsUnread ?? 0
    }

    func label(id: String) -> GmailLabel? { labels.first { $0.id == id } }

    /// User labels of a conversation, for the chips in the list and detail view.
    func userLabels(in ids: Set<String>) -> [GmailLabel] {
        labels
            .filter { ids.contains($0.id) && !$0.isSystem && !$0.isHidden }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func title(forLabel id: String) -> String {
        if id == Self.allMailID { return "Alle Nachrichten" }
        if let system = Self.systemLabels.first(where: { $0.id == id }) { return system.title }
        return label(id: id)?.name.components(separatedBy: "/").last ?? id
    }

    // MARK: - Loading

    func loadProfile() async {
        if let aliases = try? await client.sendAsAliases(),
           let primary = aliases.first(where: { $0.isDefault == true }) ?? aliases.first(where: { $0.isPrimary == true }),
           let name = primary.displayName, !name.isEmpty {
            displayName = name
        }
    }

    /// Loads all labels and their counters (one request per counted label, so this is
    /// only done on start and manual refresh; see `refreshCounts(for:)` otherwise).
    func loadLabels() async throws {
        let all = try await client.labels()
        let wanted = all.filter { label in
            Self.countedSystemLabels.contains(label.id) || (!label.isSystem && !label.isHidden)
        }
        let detailed = try await client.labels(ids: wanted.map(\.id))
        let detailedByID = Dictionary(detailed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        labels = all.map { detailedByID[$0.id] ?? $0 }
        needsReauth = false
    }

    /// Checks for changes since the last poll. Returns `true` if the mailbox changed.
    func poll(notify: Bool) async throws -> Bool {
        let profile = try await client.profile()
        defer { lastHistoryID = profile.historyId }
        guard let lastHistoryID else { return false }
        guard lastHistoryID != profile.historyId else { return false }

        if notify {
            await notifyAboutNewMessages(since: lastHistoryID)
        }
        refreshCounts(for: Self.countedSystemLabels)
        return true
    }

    // MARK: - Quota-friendly helpers

    static let countedSystemLabels: Set<String> = [SystemLabel.inbox, SystemLabel.spam]

    /// Refreshes the counters of a few labels after a change. Calls within a short
    /// window are merged into one batch, so quick actions don't flood the API.
    func refreshCounts(for ids: some Sequence<String>) {
        let known = Set(labels.map(\.id))
        let relevant = ids.filter { known.contains($0) && (Self.countedSystemLabels.contains($0) || label(id: $0)?.isSystem == false) }
        pendingCountIDs.formUnion(relevant)
        guard !pendingCountIDs.isEmpty else { return }
        countsTask?.cancel()
        countsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, !Task.isCancelled else { return }
            let batch = Array(self.pendingCountIDs)
            self.pendingCountIDs = []
            do {
                let updated = try await self.client.labels(ids: batch)
                for label in updated {
                    if let index = self.labels.firstIndex(where: { $0.id == label.id }) {
                        self.labels[index] = label
                    }
                }
            } catch {
                self.noteRateLimit(error)
            }
        }
    }

    /// Returns cached list entries for unchanged threads and fetches only the rest.
    func summaries(for refs: [GmailThreadRef]) async throws -> [ThreadSummary] {
        let stale = refs.filter { ref in
            guard let cached = summaryCache[ref.id], let historyID = ref.historyId else { return true }
            return cached.historyID != historyID
        }
        if !stale.isEmpty {
            let threads = try await client.threads(ids: stale.map(\.id), format: .metadata)
            for thread in threads {
                let summary = ThreadSummary(thread: thread, selfAddresses: [email], selfName: "Ich")
                summaryCache[thread.id] = (thread.historyId, summary)
            }
        }
        return refs.compactMap { summaryCache[$0.id]?.summary }
    }

    /// Keeps a locally changed entry (e.g. marked read) in the cache until Gmail reports a new historyId.
    func updateCachedSummary(_ summary: ThreadSummary) {
        guard let cached = summaryCache[summary.id] else { return }
        summaryCache[summary.id] = (cached.historyID, summary)
    }

    var isRateLimited: Bool {
        guard let rateLimitedUntil else { return false }
        return rateLimitedUntil > Date()
    }

    func noteRateLimit(_ error: Error) {
        if let apiError = error as? GmailAPIError, apiError.isRateLimited {
            rateLimitedUntil = Date().addingTimeInterval(60)
        }
    }

    private func notifyAboutNewMessages(since historyID: String) async {
        guard let history = try? await client.history(startHistoryID: historyID, labelID: SystemLabel.inbox) else { return }
        let added = (history.history ?? [])
            .flatMap { $0.messagesAdded ?? [] }
            .map(\.message)
            .filter { ($0.labelIds ?? []).contains(SystemLabel.unread) && ($0.labelIds ?? []).contains(SystemLabel.inbox) }

        let center = UNUserNotificationCenter.current()
        for message in added.suffix(5) {
            guard let full = try? await client.message(id: message.id, format: .metadata) else { continue }
            let content = UNMutableNotificationContent()
            content.title = full.from?.displayName ?? email
            content.subtitle = full.subject
            content.body = HTMLText.decodeEntities(full.snippet ?? "")
            content.threadIdentifier = full.threadId
            content.sound = .default
            content.userInfo = ["account": email, "thread": full.threadId]
            try? await center.add(UNNotificationRequest(identifier: full.id, content: content, trigger: nil))
        }
    }

    // MARK: - Sidebar

    private struct SystemLabelInfo {
        let id: String
        let title: String
        let systemImage: String
        let showsUnread: Bool
    }

    private static let systemLabels: [SystemLabelInfo] = [
        SystemLabelInfo(id: SystemLabel.inbox, title: "Posteingang", systemImage: "tray.fill", showsUnread: true),
        SystemLabelInfo(id: SystemLabel.starred, title: "Markiert", systemImage: "star.fill", showsUnread: false),
        SystemLabelInfo(id: SystemLabel.important, title: "Wichtig", systemImage: "bookmark.fill", showsUnread: false),
        SystemLabelInfo(id: SystemLabel.sent, title: "Gesendet", systemImage: "paperplane.fill", showsUnread: false),
        SystemLabelInfo(id: SystemLabel.draft, title: "Entwürfe", systemImage: "doc.fill", showsUnread: false),
        SystemLabelInfo(id: allMailID, title: "Alle Nachrichten", systemImage: "archivebox.fill", showsUnread: false),
        SystemLabelInfo(id: SystemLabel.spam, title: "Spam", systemImage: "exclamationmark.octagon.fill", showsUnread: true),
        SystemLabelInfo(id: SystemLabel.trash, title: "Papierkorb", systemImage: "trash.fill", showsUnread: false),
    ]

    var systemItems: [SidebarItem] {
        Self.systemLabels.map { info in
            SidebarItem(
                id: info.id,
                title: info.title,
                systemImage: info.systemImage,
                unread: info.showsUnread ? (label(id: info.id)?.threadsUnread ?? 0) : 0,
                indent: 0
            )
        }
    }

    var userItems: [SidebarItem] {
        labels
            .filter { !$0.isSystem && !$0.isHidden }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { label in
                let components = label.name.components(separatedBy: "/")
                return SidebarItem(
                    id: label.id,
                    title: components.last ?? label.name,
                    systemImage: "tag",
                    unread: label.threadsUnread ?? 0,
                    indent: components.count - 1,
                    colorHex: label.color?.backgroundColor
                )
            }
    }
}
