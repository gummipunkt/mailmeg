import AppKit
import Foundation
import MailmegKit
import Observation
import UserNotifications

struct MailboxSelection: Hashable {
    var accountID: String
    var labelID: String
}

/// Root state of the app: accounts, current mailbox and selected conversation.
@MainActor
@Observable
final class AppModel {
    private(set) var accounts: [AccountSession] = []
    private(set) var mailbox: MailboxModel?
    private(set) var threadDetail: ThreadDetailModel?
    var errorMessage: String?
    private(set) var isSigningIn = false

    var selection: MailboxSelection? {
        didSet {
            guard selection != oldValue else { return }
            openSelectedMailbox()
        }
    }

    var selectedThreadID: String? {
        didSet {
            guard selectedThreadID != oldValue else { return }
            openSelectedThread()
        }
    }

    private let auth = AuthService()
    private var pollTask: Task<Void, Never>?
    private var started = false

    init() {
        let config = AppSettings.oauthConfig
        accounts = AccountStore.emails.compactMap { email in
            guard let tokens = AccountStore.tokens(for: email) else { return nil }
            return AccountSession(email: email, tokens: tokens, config: config)
        }
    }

    func account(id: String) -> AccountSession? {
        accounts.first { $0.id == id }
    }

    // MARK: - Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        if AppSettings.notificationsEnabled {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
        if selection == nil, let first = accounts.first {
            selection = MailboxSelection(accountID: first.id, labelID: SystemLabel.inbox)
        }
        for account in accounts {
            await refreshAccount(account)
        }
        updateDockBadge()
        startPolling()
    }

    private func refreshAccount(_ account: AccountSession) async {
        await account.loadProfile()
        do {
            try await account.loadLabels()
            _ = try await account.poll(notify: false)
        } catch {
            present(error, account: account)
        }
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(AppSettings.refreshInterval))
                guard !Task.isCancelled else { return }
                await self?.pollAll()
            }
        }
    }

    func pollAll() async {
        for account in accounts where !account.needsReauth {
            do {
                let changed = try await account.poll(notify: AppSettings.notificationsEnabled)
                if changed, let mailbox, mailbox.account === account {
                    await mailbox.refreshFirstPage()
                }
            } catch let error as OAuthError where error == .invalidGrant {
                account.needsReauth = true
            } catch {
                // Transient network errors while polling are not worth an alert.
            }
        }
        updateDockBadge()
    }

    /// Manual refresh (⇧⌘N): reload labels and the visible list.
    func refreshAll() async {
        for account in accounts {
            do {
                try await account.loadLabels()
            } catch {
                present(error, account: account)
            }
        }
        await mailbox?.reload()
        await threadDetail?.load()
        updateDockBadge()
    }

    private func updateDockBadge() {
        let unread = accounts.reduce(0) { $0 + $1.inboxUnread }
        NSApp.dockTile.badgeLabel = unread > 0 ? String(unread) : nil
    }

    // MARK: - Accounts

    func signIn(loginHint: String? = nil) async {
        let config = AppSettings.oauthConfig
        guard config.isValid else {
            errorMessage = String(localized: "Please enter a valid Google OAuth client ID first (it ends with .apps.googleusercontent.com).")
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let tokens = try await auth.authorize(config: config, loginHint: loginHint)
            let probe = GmailClient(tokens: TokenManager(tokens: tokens, oauth: GoogleOAuthClient(config: config), onUpdate: { _ in }))
            let email = try await probe.profile().emailAddress
            try AccountStore.add(email, tokens: tokens)

            let session = AccountSession(email: email, tokens: tokens, config: config)
            if let index = accounts.firstIndex(where: { $0.id == email }) {
                accounts[index] = session
            } else {
                accounts.append(session)
            }
            await refreshAccount(session)
            let inbox = MailboxSelection(accountID: email, labelID: SystemLabel.inbox)
            if selection == inbox {
                openSelectedMailbox()
            } else {
                selection = inbox
            }
            updateDockBadge()
            if pollTask == nil { startPolling() }
        } catch {
            if !AuthService.isCancellation(error) {
                present(error)
            }
        }
    }

    func remove(_ account: AccountSession) async {
        if let tokens = AccountStore.tokens(for: account.email) {
            try? await GoogleOAuthClient(config: AppSettings.oauthConfig).revoke(token: tokens.refreshToken)
        }
        AccountStore.remove(account.email)
        accounts.removeAll { $0.id == account.id }
        if selection?.accountID == account.id {
            selection = accounts.first.map { MailboxSelection(accountID: $0.id, labelID: SystemLabel.inbox) }
        }
        updateDockBadge()
    }

    // MARK: - Selection

    private func openSelectedMailbox() {
        threadDetail = nil
        selectedThreadID = nil
        guard let selection, let account = account(id: selection.accountID) else {
            mailbox = nil
            return
        }
        let mailbox = MailboxModel(account: account, labelID: selection.labelID)
        mailbox.onError = { [weak self] error in self?.present(error, account: account) }
        self.mailbox = mailbox
        Task { await mailbox.reload() }
    }

    private func openSelectedThread() {
        guard let mailbox, let threadID = selectedThreadID else {
            threadDetail = nil
            return
        }
        let detail = ThreadDetailModel(account: mailbox.account, threadID: threadID)
        detail.onMarkedRead = { [weak mailbox] id in mailbox?.markLocallyRead(id) }
        detail.onError = { [weak self] error in self?.present(error, account: mailbox.account) }
        threadDetail = detail
        Task { await detail.load() }
    }

    // MARK: - Actions on the selected thread

    var selectedThread: ThreadSummary? { mailbox?.thread(id: selectedThreadID) }

    func perform(_ action: ThreadAction, threadID: String? = nil) {
        guard let mailbox, let id = threadID ?? selectedThreadID else { return }
        let ids = mailbox.threads.map(\.id)
        let position = ids.firstIndex(of: id)
        Task {
            let removed = await mailbox.perform(action, on: id)
            if removed, id == selectedThreadID {
                // Move the selection to the next conversation, like Mail does.
                let remaining = mailbox.threads
                if let position, !remaining.isEmpty {
                    selectedThreadID = remaining[min(position, remaining.count - 1)].id
                } else {
                    selectedThreadID = nil
                }
            } else if id == selectedThreadID, action == .markRead || action == .markUnread || action == .star || action == .unstar {
                await threadDetail?.load()
            }
            updateDockBadge()
        }
    }

    func toggleRead() {
        guard let thread = selectedThread else { return }
        perform(thread.isUnread ? .markRead : .markUnread)
    }

    func toggleStar() {
        guard let thread = selectedThread else { return }
        perform(thread.isStarred ? .unstar : .star)
    }

    // MARK: - Compose

    func newDraft(to recipient: String = "") -> ComposeDraft {
        let accountID = selection?.accountID ?? accounts.first?.id ?? ""
        var draft = ComposeDraft(accountID: accountID)
        draft.to = recipient
        return draft
    }

    func replyDraft(_ kind: ComposeKind) -> ComposeDraft? {
        threadDetail?.draft(kind)
    }

    func didSend(from account: AccountSession) {
        Task {
            try? await account.loadLabels()
            if mailbox?.account === account {
                await mailbox?.refreshFirstPage()
            }
            if threadDetail?.account === account {
                await threadDetail?.load()
            }
        }
    }

    // MARK: - Errors

    func present(_ error: Error, account: AccountSession? = nil) {
        if let oauthError = error as? OAuthError, oauthError == .invalidGrant {
            account?.needsReauth = true
        }
        errorMessage = error.localizedDescription
    }
}
