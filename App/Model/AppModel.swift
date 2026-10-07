import AppKit
import Foundation
import MailmegKit
import Observation
import UserNotifications

struct MailboxSelection: Hashable {
    var accountID: String
    var labelID: String
}

/// The two tabs of the main window.
enum AppSection: Hashable {
    case mail, calendar
}

/// Root state of the app: accounts, current mailbox and selected conversation.
@MainActor
@Observable
final class AppModel {
    private(set) var accounts: [AccountSession] = []
    private(set) var mailbox: MailboxModel?
    private(set) var threadDetail: ThreadDetailModel?
    /// Mail or calendar, switched with the tabs at the top of the sidebar.
    private(set) var section: AppSection = .mail
    /// The calendar tab; created the first time it is opened, then kept.
    private(set) var calendarView: CalendarViewState?
    private(set) var selection: MailboxSelection?
    private(set) var selectedThreadID: String?
    private(set) var isSigningIn = false
    private(set) var isDemo = false
    /// True while the saved accounts are being read from the keychain at launch.
    private(set) var isLoadingAccounts = false
    /// When mail was last fetched (automatically or manually).
    private(set) var lastRefresh: Date?
    private(set) var isRefreshing = false
    var errorMessage: String?

    private let auth = AuthService()
    private var pollTask: Task<Void, Never>?
    private var started = false

    init() {
        MailNotifications.shared.configure(model: self)
        if LaunchOptions.demo {
            isDemo = true
            accounts = [DemoMailbox.makeSession()]
            return
        }
        guard !LaunchOptions.onboarding else { return }
        // The keychain is read in `start()`, off the main thread: macOS may ask for
        // keychain access after an update, and that must not block the app's launch.
        isLoadingAccounts = !AccountStore.emails.isEmpty
    }

    /// Reads the saved sign-ins from the keychain in the background.
    private func loadStoredAccounts() async {
        let emails = AccountStore.emails
        let config = AppSettings.oauthConfig
        let stored: [(email: String, tokens: OAuthTokens)] = await Task.detached(priority: .userInitiated) {
            emails.compactMap { email in AccountStore.tokens(for: email).map { (email: email, tokens: $0) } }
        }.value
        accounts = stored.map { AccountSession(email: $0.email, tokens: $0.tokens, config: config) }
        isLoadingAccounts = false
        let missing = emails.filter { email in !stored.contains { $0.email == email } }
        if !missing.isEmpty {
            errorMessage = tr(
                "MailMeG konnte die Anmeldung für \(missing.joined(separator: ", ")) nicht aus dem Schlüsselbund lesen. Falls macOS nach dem Schlüsselbund gefragt hat, wähle beim nächsten Start „Immer erlauben“ – oder melde dich einfach erneut an.",
                "MailMeG couldn’t read the sign-in for \(missing.joined(separator: ", ")) from the keychain. If macOS asked about the keychain, choose “Always Allow” next time – or simply sign in again."
            )
        }
    }

    func account(id: String) -> AccountSession? {
        accounts.first { $0.id == id }
    }

    // MARK: - Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        if isLoadingAccounts {
            await loadStoredAccounts()
        }
        observeUnread()
        if !isDemo {
            // Also covers the unread counter on the Dock icon.
            await MailNotifications.shared.requestAuthorization()
        }
        if selection == nil, let first = accounts.first {
            select(MailboxSelection(accountID: first.id, labelID: SystemLabel.inbox))
        }
        for account in accounts {
            await refreshAccount(account)
        }
        lastRefresh = Date()
        updateDockBadge()
        startPolling()
        await loadTodayEvents()
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
        pollTask = nil
        guard AppSettings.refreshInterval > 0 else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = AppSettings.refreshInterval
                guard interval > 0 else { return }
                try? await Task.sleep(for: .seconds(interval))
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
        for account in accounts where !account.needsReauth {
            await account.calendar.refreshIfStale(maxAge: 300)
        }
        lastRefresh = Date()
        updateDockBadge()
    }

    /// Manual refresh (⇧⌘N): reload labels and the visible list.
    func refreshAll() async {
        isRefreshing = true
        defer {
            isRefreshing = false
            lastRefresh = Date()
        }
        for account in accounts {
            do {
                try await account.loadLabels()
            } catch {
                present(error, account: account)
            }
        }
        await mailbox?.reload()
        await threadDetail?.load()
        for account in accounts {
            await account.calendar.refresh()
        }
        updateDockBadge()
    }

    /// Unread conversations in all inboxes, shown on the Dock icon.
    var totalInboxUnread: Int { accounts.reduce(0) { $0 + $1.inboxUnread } }

    func updateDockBadge() {
        let unread = AppSettings.dockBadgeEnabled ? totalInboxUnread : 0
        NSApp.dockTile.badgeLabel = unread > 0 ? (unread > 9999 ? "9999+" : String(unread)) : nil
    }

    /// Keeps the Dock badge in step with the unread counters, whatever changed them.
    private func observeUnread() {
        withObservationTracking {
            _ = totalInboxUnread
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateDockBadge()
                self?.observeUnread()
            }
        }
    }

    // MARK: - Accounts

    func signIn(loginHint: String? = nil) async {
        let config = AppSettings.oauthConfig
        guard config.isValid else {
            errorMessage = tr("Bitte gib zuerst eine gültige Google-OAuth-Client-ID ein (sie endet auf .apps.googleusercontent.com).", "Please enter a valid Google OAuth client ID first (it ends with .apps.googleusercontent.com).")
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
        detail.onMarkedRead = { [weak mailbox] id in
            mailbox?.markLocallyRead(id)
            MailNotifications.shared.removeNotifications(threadID: id)
        }
        detail.onError = { [weak self] error in self?.present(error, account: mailbox.account) }
        detail.onDraftsChanged = { [weak self, weak mailbox] in
            guard let self, let mailbox else { return }
            Task {
                await mailbox.refreshFirstPage()
                if mailbox.thread(id: threadID) == nil {
                    self.selectThread(nil)
                } else {
                    await self.threadDetail?.load()
                }
            }
        }
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
            } else if id == selectedThreadID, Self.reloadsDetail(action) {
                await threadDetail?.load()
            }
            updateDockBadge()
        }
    }

    private static func reloadsDetail(_ action: ThreadAction) -> Bool {
        switch action {
        case .markRead, .markUnread, .star, .unstar, .addLabel, .removeLabel: return true
        default: return false
        }
    }

    /// Selects the previous (-1) or next (+1) conversation in the list.
    func selectAdjacentThread(_ offset: Int) {
        guard let threads = mailbox?.threads, !threads.isEmpty else { return }
        guard let id = selectedThreadID, let index = threads.firstIndex(where: { $0.id == id }) else {
            selectThread(threads.first?.id)
            return
        }
        let target = index + offset
        guard threads.indices.contains(target) else { return }
        selectThread(threads[target].id)
    }

    func canSelectAdjacentThread(_ offset: Int) -> Bool {
        guard let threads = mailbox?.threads, let id = selectedThreadID,
              let index = threads.firstIndex(where: { $0.id == id }) else { return false }
        return threads.indices.contains(index + offset)
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
        let target = selection.flatMap { self.account(id: $0.accountID) } ?? accounts.first
        return DraftComposer.newDraft(account: target, to: recipient)
    }

    /// Refreshes the Drafts list after a draft was saved, sent or discarded.
    func draftsChanged(_ account: AccountSession) {
        guard let mailbox, mailbox.account === account, mailbox.labelID == SystemLabel.draft else { return }
        Task {
            await mailbox.refreshFirstPage()
            if let id = selectedThreadID, mailbox.thread(id: id) == nil {
                selectThread(nil)
            }
        }
    }

    /// Loads the draft of a conversation for editing (double-click in the Drafts folder).
    func openDraft(threadID: String) async -> ComposeDraft? {
        guard let account = mailbox?.account else { return nil }
        do {
            let messages = try await account.client.thread(id: threadID, format: .full).messages ?? []
            guard let draftMessage = messages.last(where: \.isDraft) else { return nil }
            return await DraftComposer.editableDraft(from: draftMessage, in: messages, account: account)
        } catch {
            present(error, account: account)
            return nil
        }
    }

    /// All sender identities across accounts, for the "From" menu.
    var allIdentities: [SenderIdentity] { accounts.flatMap(\.identities) }

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

    // MARK: - Calendar

    /// Switches to the mail or calendar tab.
    func show(_ section: AppSection) {
        if section == .calendar {
            showCalendar()
        } else {
            self.section = .mail
        }
    }

    /// Opens the calendar tab, optionally on `day` with an event (`CalendarEvent.key`) selected.
    func showCalendar(accountID: String? = nil, day: Date? = nil, eventID: String? = nil) {
        let view = calendarView ?? CalendarViewState { [weak self] in self?.accounts ?? [] }
        calendarView = view
        section = .calendar
        if let day {
            view.select(day: day)
        }
        if let eventID, let accountID = accountID ?? selection?.accountID {
            view.selectedEventID = CalendarEntry.id(accountID: accountID, eventKey: eventID)
            view.revealSelectedEvent()
        } else if day != nil {
            view.selectedEventID = nil
        }
        Task { await view.load() }
    }

    /// After a new event was added: show it if the calendar is on screen.
    func eventCreated(_ event: CalendarEvent, accountID: String) {
        guard let view = calendarView, section == .calendar else { return }
        view.select(day: event.startDate ?? Date())
        view.selectedEventID = CalendarEntry.id(accountID: accountID, eventKey: event.key)
        view.revealSelectedEvent()
    }

    /// A new event, for the account of the open mailbox and the day currently shown.
    func newEventDraft() -> EventDraft {
        let accountID = selection?.accountID ?? accounts.first?.id ?? ""
        return EventDraft.new(accountID: accountID, day: section == .calendar ? calendarView?.selectedDay : nil)
    }

    /// A new event prefilled from the newest message of the open conversation.
    func eventDraftFromSelectedMessage() -> EventDraft? {
        guard let detail = threadDetail,
              let message = detail.messages.last(where: { !$0.message.isDraft })?.message ?? detail.latestMessage else { return nil }
        return EventDraft.from(message, account: detail.account)
    }

    /// Loads today's events of all accounts for the "Today" list in the sidebar.
    func loadTodayEvents() async {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        for account in accounts {
            await account.calendar.ensureLoaded(DateInterval(start: start, end: end))
        }
    }

    // MARK: - Notifications

    /// Click on a notification: bring MailMeG to the front and open the conversation.
    func openFromNotification(accountID: String, threadID: String) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }?.makeKeyAndOrderFront(nil)
        guard account(id: accountID) != nil else { return }
        section = .mail
        if selection?.accountID != accountID || mailbox?.thread(id: threadID) == nil {
            select(MailboxSelection(accountID: accountID, labelID: SystemLabel.inbox))
        }
        selectThread(threadID)
    }

    /// "Mark as Read" / "Archive" from a notification.
    func notificationAction(_ action: ThreadAction, accountID: String, threadID: String) async {
        guard let account = account(id: accountID) else { return }
        if let mailbox, mailbox.account === account, mailbox.thread(id: threadID) != nil {
            perform(action, threadID: threadID)
        } else {
            do {
                try await MailboxModel.sync(action, threadID: threadID, client: account.client)
                account.refreshCounts(for: [SystemLabel.inbox])
            } catch {
                present(error, account: account)
            }
        }
        MailNotifications.shared.removeNotifications(threadID: threadID)
    }

    /// "Reply" typed right into a notification.
    func replyFromNotification(_ text: String, accountID: String, threadID: String) async {
        guard let account = account(id: accountID) else { return }
        let detail = ThreadDetailModel(account: account, threadID: threadID)
        await detail.load()
        if let error = detail.loadError {
            errorMessage = error
            return
        }
        do {
            try await detail.sendQuickReply(text, replyAll: false)
            didSend(from: account)
        } catch {
            present(error, account: account)
        }
        MailNotifications.shared.removeNotifications(threadID: threadID)
    }

    // MARK: - Errors

    func present(_ error: Error, account: AccountSession? = nil) {
        if let oauthError = error as? OAuthError, oauthError == .invalidGrant {
            account?.needsReauth = true
        }
        if let apiError = error as? GmailAPIError, apiError.isRateLimited {
            account?.noteRateLimit(error)
            errorMessage = tr("Google hat kurzzeitig zu viele Anfragen gezählt (Gmail-Kontingent pro Minute). MailMeG pausiert die automatische Aktualisierung für eine Minute, danach geht es normal weiter.", "Google counted too many requests for a moment (Gmail quota per minute). MailMeG pauses automatic refreshing for a minute, then carries on as usual.")
            return
        }
        errorMessage = error.localizedDescription
    }
}

enum LaunchOptions {
    static var demo: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo") || ProcessInfo.processInfo.environment["MAILMEG_DEMO"] == "1"
    }

    /// `--lang=en` / `--lang=de` overrides the system language (used for screenshots).
    static var language: String? {
        ProcessInfo.processInfo.arguments.first { $0.hasPrefix("--lang=") }.map { String($0.dropFirst("--lang=".count)) }
    }

    static var onboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("--onboarding")
    }

    /// UI tests: the Google Drive button uploads a generated file (demo mode only).
    static var driveTestFile: Bool {
        ProcessInfo.processInfo.arguments.contains("--drive-test-file")
    }

    /// Clean screenshots for the website: no spell-check underlines.
    static var screenshots: Bool {
        ProcessInfo.processInfo.arguments.contains("--screenshots")
    }

    /// Forces dark appearance (used for screenshots).
    static var dark: Bool {
        ProcessInfo.processInfo.arguments.contains("--dark")
    }
}
