import Foundation
import MailmegKit
import Observation

enum ThreadAction: Equatable {
    case archive, moveToInbox, trash, untrash, markRead, markUnread, star, unstar, reportSpam, notSpam
    case addLabel(String), removeLabel(String)
    /// Files a conversation under a label and takes it out of the one it came from.
    case move(to: String, from: String?)

    /// What takes a conversation back to how it was before this action (for Undo).
    /// `original` is the conversation before the action, `mailboxID` the list it was in.
    func inverse(for original: ThreadSummary, in mailboxID: String) -> [ThreadAction] {
        let labels = original.labelIDs
        let wasInInbox = labels.contains(SystemLabel.inbox)
        switch self {
        case .archive:
            return wasInInbox ? [.moveToInbox] : []
        case .moveToInbox:
            if mailboxID == SystemLabel.trash { return [.trash] }
            if mailboxID == SystemLabel.spam { return [.reportSpam] }
            return wasInInbox ? [] : [.archive]
        case .trash:
            // Gmail takes a trashed conversation out of the inbox, so put it back there.
            return wasInInbox ? [.moveToInbox] : [.untrash]
        case .untrash:
            return [.trash]
        case .markRead:
            return original.isUnread ? [.markUnread] : []
        case .markUnread:
            return original.isUnread ? [] : [.markRead]
        case .star:
            return original.isStarred ? [] : [.unstar]
        case .unstar:
            return original.isStarred ? [.star] : []
        case .reportSpam:
            return wasInInbox ? [.notSpam] : [.removeLabel(SystemLabel.spam)]
        case .notSpam:
            return [.reportSpam]
        case .addLabel(let id):
            return labels.contains(id) ? [] : [.removeLabel(id)]
        case .removeLabel(let id):
            return labels.contains(id) ? [.addLabel(id)] : []
        case .move(let target, let source):
            let hadTarget = labels.contains(target)
            guard let source else { return hadTarget ? [] : [.removeLabel(target)] }
            return [hadTarget ? .addLabel(source) : .move(to: source, from: target)]
        }
    }

    /// The labels whose counts this action changes.
    var touchedLabelIDs: [String] {
        switch self {
        case .addLabel(let id), .removeLabel(let id): return [id]
        case .move(let target, let source): return [target] + (source.map { [$0] } ?? [])
        case .trash, .untrash: return [SystemLabel.inbox, SystemLabel.trash]
        default: return [SystemLabel.inbox, SystemLabel.spam]
        }
    }

    /// The name shown in the Edit menu: “Undo Archive”.
    var undoName: String {
        switch self {
        case .archive: return tr("Archivieren", "Archive")
        case .moveToInbox: return tr("In den Posteingang bewegen", "Move to Inbox")
        case .trash: return tr("In den Papierkorb legen", "Move to Trash")
        case .untrash: return tr("Wiederherstellen", "Restore")
        case .markRead: return tr("Als gelesen markieren", "Mark as Read")
        case .markUnread: return tr("Als ungelesen markieren", "Mark as Unread")
        case .star: return tr("Markieren", "Star")
        case .unstar: return tr("Markierung entfernen", "Remove Star")
        case .reportSpam: return tr("Als Spam melden", "Report Spam")
        case .notSpam: return tr("Kein Spam", "Not Spam")
        case .addLabel: return tr("Label hinzufügen", "Add Label")
        case .removeLabel: return tr("Label entfernen", "Remove Label")
        case .move: return tr("Bewegen", "Move")
        }
    }
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
        // Without a next page the fresh list is complete: whatever is missing from it has left
        // this mailbox (archived, moved or undone elsewhere).
        let tail = token == nil ? [] : threads.filter { !freshIDs.contains($0.id) && ($0.date ?? .distantPast) < oldestFresh }
        threads = fresh + tail
        if tail.isEmpty { nextPageToken = token }
    }

    func loadMoreIfNeeded(after thread: ThreadSummary) {
        guard thread.id == threads.last?.id, nextPageToken != nil, !isLoadingMore, !isLoading else { return }
        Task { await loadMore() }
    }

    /// Loads further pages until the list is complete or holds `limit` conversations.
    func loadAll(limit: Int) async {
        while nextPageToken != nil, threads.count < limit {
            if isLoadingMore || isLoading {
                try? await Task.sleep(for: .milliseconds(100))
                continue
            }
            let before = threads.count
            await loadMore()
            if threads.count == before { break }
        }
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
        case .addLabel(let id):
            updated.labelIDs.insert(id)
        case .removeLabel(let id):
            updated.labelIDs.remove(id)
            removes = labelID == id
        case .move(let target, let source):
            updated.labelIDs.insert(target)
            if let source {
                updated.labelIDs.remove(source)
                removes = labelID == source
            }
        }

        if removes {
            threads.remove(at: index)
        } else {
            threads[index] = updated
        }

        do {
            try await Self.sync(action, threadID: threadID, client: account.client)
            account.refreshCounts(for: original.labelIDs.union(updated.labelIDs).union([SystemLabel.inbox, SystemLabel.spam, labelID]))
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

    /// Shows conversations again the way they were before an action (Undo). Gmail is told
    /// separately; `index` is where each one stood in the list.
    func putBack(_ entries: [(index: Int, summary: ThreadSummary)]) {
        for entry in entries.sorted(by: { $0.index < $1.index }) {
            if let current = threads.firstIndex(where: { $0.id == entry.summary.id }) {
                threads[current] = entry.summary
            } else {
                threads.insert(entry.summary, at: min(entry.index, threads.count))
            }
            account.updateCachedSummary(entry.summary)
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
        // Also out of the trash: this is what dragging a deleted conversation to the inbox does.
        case .moveToInbox: try await client.modifyThread(id: threadID, add: [SystemLabel.inbox], remove: [SystemLabel.spam, SystemLabel.trash])
        case .trash: try await client.trashThread(id: threadID)
        case .untrash: try await client.untrashThread(id: threadID)
        case .markRead: try await client.modifyThread(id: threadID, remove: [SystemLabel.unread])
        case .markUnread: try await client.modifyThread(id: threadID, add: [SystemLabel.unread])
        case .star: try await client.modifyThread(id: threadID, add: [SystemLabel.starred])
        case .unstar: try await client.modifyThread(id: threadID, remove: [SystemLabel.starred])
        case .reportSpam: try await client.modifyThread(id: threadID, add: [SystemLabel.spam], remove: [SystemLabel.inbox])
        case .notSpam: try await client.modifyThread(id: threadID, add: [SystemLabel.inbox], remove: [SystemLabel.spam])
        case .addLabel(let id): try await client.modifyThread(id: threadID, add: [id])
        case .removeLabel(let id): try await client.modifyThread(id: threadID, remove: [id])
        case .move(let target, let source): try await client.modifyThread(id: threadID, add: [target], remove: source.map { [$0] } ?? [])
        }
    }
}
