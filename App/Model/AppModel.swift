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
    private(set) var selection: MailboxSelection?
    private(set) var selectedThreadID: String?
    private(set) var isSigningIn = false
    private(set) var isDemo = false
    var errorMessage: String?

    private let auth = AuthService()
    private var pollTask: Task<Void, Never>?
    private var started = false

    init() {
        if LaunchOptions.demo {
            isDemo = true
            accounts = [DemoMailbox.makeSession()]
            return
        }
        guard !LaunchOptions.onboarding else { return }
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
        if AppSettings.notificationsEnabled, !isDemo {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
        if selection == nil, let first = accounts.first {
            select(MailboxSelection(accountID: first.id, labelID: SystemLabel.inbox))
        }
        for account in accounts {
            await refreshAccount(account)
        }
        updateDockBadge()
        startPolling()
    }

    /// Lets people try the app without a Google account.
    func startDemo() async {
        isDemo = true
        accounts = [DemoMailbox.makeSession()]
        started = false
        await start()
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
        for account in accounts where !account.needsReauth && !account.isRateLimited {
            do {
                let changed = try await account.poll(notify: AppSettings.notificationsEnabled && !isDemo)
                if changed, let mailbox, mailbox.account === account {
                    await mailbox.refreshFirstPage()
                }
            } catch let error as OAuthError where error == .invalidGrant {
                account.needsReauth = true
            } catch {
                // Transient network errors while polling are not worth an alert.
                account.noteRateLimit(error)
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
            errorMessage = "Bitte gib zuerst eine gültige Google-OAuth-Client-ID ein (sie endet auf .apps.googleusercontent.com)."
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let tokens = try await auth.authorize(config: config, loginHint: loginHint)
            let probe = GmailClient(tokens: TokenManager(tokens: tokens, oauth: GoogleOAuthClient(config: config), onUpdate: { _ in }))
            let email = try await probe.profile().emailAddress
            try AccountStore.add(email, tokens: tokens)

            if isDemo {
                isDemo = false
                accounts = []
            }
            let session = AccountSession(email: email, tokens: tokens, config: config)
            if let index = accounts.firstIndex(where: { $0.id == email }) {
                accounts[index] = session
            } else {
                accounts.append(session)
            }
            await refreshAccount(session)
            select(MailboxSelection(accountID: email, labelID: SystemLabel.inbox), force: true)
            updateDockBadge()
            if pollTask == nil { startPolling() }
        } catch {
            if !AuthService.isCancellation(error) {
                present(error)
            }
        }
    }

    func remove(_ account: AccountSession) async {
        if !isDemo, let tokens = AccountStore.tokens(for: account.email) {
            try? await GoogleOAuthClient(config: AppSettings.oauthConfig).revoke(token: tokens.refreshToken)
        }
        if !isDemo {
            AccountStore.remove(account.email)
        }
        accounts.removeAll { $0.id == account.id }
        if accounts.isEmpty {
            isDemo = false
        }
        if selection?.accountID == account.id {
            select(accounts.first.map { MailboxSelection(accountID: $0.id, labelID: SystemLabel.inbox) })
        }
        updateDockBadge()
    }

    // MARK: - Selection

    func select(_ newSelection: MailboxSelection?, force: Bool = false) {
        DebugLog.log("select(\(newSelection?.labelID ?? "nil")) current=\(selection?.labelID ?? "nil")")
        guard force || newSelection != selection else { return }
        selection = newSelection
        selectThread(nil)
        guard let newSelection, let account = account(id: newSelection.accountID) else {
            mailbox = nil
            return
        }
        let mailbox = MailboxModel(account: account, labelID: newSelection.labelID)
        mailbox.onError = { [weak self] error in self?.present(error, account: account) }
        self.mailbox = mailbox
        Task { await mailbox.reload() }
    }

    func selectThread(_ threadID: String?) {
        guard threadID != selectedThreadID || (threadID != nil && threadDetail == nil) else { return }
        selectedThreadID = threadID
        guard let mailbox, let threadID else {
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
        let position = mailbox.threads.firstIndex { $0.id == id }
        Task {
            let removed = await mailbox.perform(action, on: id)
            if removed, id == selectedThreadID {
                // Move the selection to the next conversation, like Mail does.
                let remaining = mailbox.threads
                if let position, !remaining.isEmpty {
                    selectThread(remaining[min(position, remaining.count - 1)].id)
                } else {
                    selectThread(nil)
                }
            } else if id == selectedThreadID, [.markRead, .markUnread, .star, .unstar].contains(action) {
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
            account.refreshCounts(for: [SystemLabel.inbox, SystemLabel.sent])
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
        if let apiError = error as? GmailAPIError, apiError.isRateLimited {
            account?.noteRateLimit(error)
            errorMessage = "Google hat kurzzeitig zu viele Anfragen gezählt (Gmail-Kontingent pro Minute). Mailmeg pausiert die automatische Aktualisierung für eine Minute, danach geht es normal weiter."
            return
        }
        errorMessage = error.localizedDescription
    }
}

enum LaunchOptions {
    static var demo: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo") || ProcessInfo.processInfo.environment["MAILMEG_DEMO"] == "1"
    }

    static var onboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("--onboarding")
    }

    /// Forces dark appearance (used for screenshots).
    static var dark: Bool {
        ProcessInfo.processInfo.arguments.contains("--dark")
    }
}
