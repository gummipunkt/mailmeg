import Foundation
import MailmegKit
import Observation

enum ThreadAction {
    case archive, moveToInbox, trash, untrash, markRead, markUnread, star, unstar, reportSpam, notSpam
}

/// The thread list for one label of one account, including search and paging.
@MainActor
@Observable
final class MailboxModel {
    static let pageSize = 50

    let account: AccountSession
    let labelID: String

    var threads: [ThreadSummary] = []
    var searchText = ""
    private(set) var activeQuery = ""
    /// Shows only unread conversations (adds `is:unread` to the query).
    private(set) var unreadOnly = false

    func setUnreadOnly(_ value: Bool) {
        guard value != unreadOnly else { return }
        unreadOnly = value
        Task { await reload() }
    }
    private(set) var nextPageToken: String?
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var hasLoaded = false
    var onError: ((Error) -> Void)?

    private var generation = 0

    init(account: AccountSession, labelID: String) {
        self.account = account
        self.labelID = labelID
    }

    var title: String {
        activeQuery.isEmpty ? account.title(forLabel: labelID) : tr("Suche", "Search")
    }

    private var labelIDs: [String] {
        labelID == AccountSession.allMailID ? [] : [labelID]
    }

    func thread(id: String?) -> ThreadSummary? {
        guard let id else { return nil }
        return threads.first { $0.id == id }
    }

    // MARK: - Loading

    func submitSearch() {
        activeQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await reload() }
    }

    func reload() async {
        generation += 1
        let current = generation
        isLoading = true
        defer { if current == generation { isLoading = false } }
        do {
            let (summaries, token) = try await fetchPage(pageToken: nil)
            guard current == generation else { return }
            threads = summaries
            nextPageToken = token
            hasLoaded = true
        } catch {
            guard current == generation else { return }
            onError?(error)
        }
    }

    /// Re-fetches the first page and merges it with what is already loaded,
    /// so polling does not throw away pages the user scrolled to.
    func refreshFirstPage() async {
        guard hasLoaded, !isLoading, !account.isRateLimited else { return }
        let current = generation
        guard let page = try? await fetchPage(pageToken: nil), current == generation else { return }
        let (fresh, token) = page
        let freshIDs = Set(fresh.map(\.id))
        let oldestFresh = fresh.last?.date ?? .distantFuture
        let tail = threads.filter { !freshIDs.contains($0.id) && ($0.date ?? .distantPast) < oldestFresh }
        threads = fresh + tail
        if tail.isEmpty { nextPageToken = token }
    }

    func loadMoreIfNeeded(after thread: ThreadSummary) {
        guard thread.id == threads.last?.id, nextPageToken != nil, !isLoadingMore, !isLoading else { return }
        Task { await loadMore() }
    }

    func loadMore() async {
        guard let token = nextPageToken, !isLoadingMore else { return }
        let current = generation
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let (summaries, next) = try await fetchPage(pageToken: token)
            guard current == generation else { return }
            let existing = Set(threads.map(\.id))
            threads += summaries.filter { !existing.contains($0.id) }
            nextPageToken = next
        } catch {
            onError?(error)
        }
    }

    private func fetchPage(pageToken: String?) async throws -> ([ThreadSummary], String?) {
        let list = try await account.client.listThreads(
            labelIDs: labelIDs,
            query: effectiveQuery,
            pageToken: pageToken,
            maxResults: Self.pageSize
        )
        let summaries = try await account.summaries(for: list.threads ?? [])
        return (summaries, list.nextPageToken)
    }

    private var effectiveQuery: String? {
        let parts = [activeQuery, unreadOnly ? "is:unread" : ""].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    var unreadCount: Int {
        account.label(id: labelID)?.threadsUnread ?? threads.filter(\.isUnread).count
    }

    // MARK: - Actions

    /// Applies an action optimistically, then syncs it to Gmail.
    /// Returns `true` if the thread disappeared from this list.
    @discardableResult
    func perform(_ action: ThreadAction, on threadID: String) async -> Bool {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return false }
        let original = threads[index]
        var updated = original
        var removes = false

        switch action {
        case .archive:
            updated.labelIDs.remove(SystemLabel.inbox)
            removes = labelID == SystemLabel.inbox
        case .moveToInbox:
            updated.labelIDs.insert(SystemLabel.inbox)
            removes = labelID == SystemLabel.trash || labelID == SystemLabel.spam
        case .trash:
            removes = labelID != SystemLabel.trash
        case .untrash:
            removes = labelID == SystemLabel.trash
        case .markRead:
            updated.isUnread = false
        case .markUnread:
            updated.isUnread = true
        case .star:
            updated.isStarred = true
        case .unstar:
            updated.isStarred = false
            removes = labelID == SystemLabel.starred
        case .reportSpam:
            removes = labelID != SystemLabel.spam
        case .notSpam:
            removes = labelID == SystemLabel.spam
        }

        if removes {
            threads.remove(at: index)
        } else {
            threads[index] = updated
        }

        do {
            try await Self.sync(action, threadID: threadID, client: account.client)
            account.refreshCounts(for: original.labelIDs.union([SystemLabel.inbox, SystemLabel.spam, labelID]))
            if !removes { account.updateCachedSummary(updated) }
            return removes
        } catch {
            if removes {
                threads.insert(original, at: min(index, threads.count))
            } else if let current = threads.firstIndex(where: { $0.id == threadID }) {
                threads[current] = original
            }
            onError?(error)
            return false
        }
    }

    /// Updates local state after the detail view marked a thread as read.
    func markLocallyRead(_ threadID: String) {
        guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[index].isUnread = false
        account.updateCachedSummary(threads[index])
    }

    static func sync(_ action: ThreadAction, threadID: String, client: GmailClient) async throws {
        switch action {
        case .archive: try await client.modifyThread(id: threadID, remove: [SystemLabel.inbox])
        case .moveToInbox: try await client.modifyThread(id: threadID, add: [SystemLabel.inbox], remove: [SystemLabel.spam])
        case .trash: try await client.trashThread(id: threadID)
        case .untrash: try await client.untrashThread(id: threadID)
        case .markRead: try await client.modifyThread(id: threadID, remove: [SystemLabel.unread])
        case .markUnread: try await client.modifyThread(id: threadID, add: [SystemLabel.unread])
        case .star: try await client.modifyThread(id: threadID, add: [SystemLabel.starred])
        case .unstar: try await client.modifyThread(id: threadID, remove: [SystemLabel.starred])
        case .reportSpam: try await client.modifyThread(id: threadID, add: [SystemLabel.spam], remove: [SystemLabel.inbox])
        case .notSpam: try await client.modifyThread(id: threadID, add: [SystemLabel.inbox], remove: [SystemLabel.spam])
        }
    }
}
