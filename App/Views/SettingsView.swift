import AppKit
import MailmegKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(tr("Allgemein", "General"), systemImage: "gearshape") }
            ComposeSettingsView()
                .tabItem { Label(tr("Verfassen", "Composing"), systemImage: "square.and.pencil") }
            AccountsSettingsView()
                .tabItem { Label(tr("Konten", "Accounts"), systemImage: "person.crop.circle") }
            AboutSettingsView()
                .tabItem { Label(tr("Über", "About"), systemImage: "info.circle") }
        }
        .frame(width: 540)
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppSettings.loadRemoteContentKey) private var loadRemoteContent = false
    @AppStorage(AppSettings.notificationsKey) private var notificationsEnabled = true
    @AppStorage(AppSettings.refreshIntervalKey) private var refreshInterval: Double = 60
    @AppStorage(AppSettings.showAvatarsKey) private var showAvatars = false

    private var lastRefreshText: String {
        guard let date = model.lastRefresh else { return tr("Noch nicht abgerufen", "Not checked yet") }
        return tr("Zuletzt abgerufen: \(date.formatted(date: .omitted, time: .shortened))", "Last checked: \(date.formatted(date: .omitted, time: .shortened))")
    }

    var body: some View {
        Form {
            Section {
                Picker(tr("Nach neuen E-Mails suchen", "Check for new email"), selection: $refreshInterval) {
                    ForEach(AppSettings.refreshOptions) { option in
                        Text(option.title).tag(option.seconds)
                    }
                }
                .onChange(of: refreshInterval) { model.startPolling() }
                .accessibilityIdentifier("settings.refreshInterval")
                HStack {
                    Text(lastRefreshText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(tr("Jetzt abrufen", "Check Now")) { Task { await model.refreshAll() } }
                        .disabled(model.isRefreshing)
                }
                Toggle(tr("Mitteilungen bei neuen E-Mails", "Notify me about new email"), isOn: $notificationsEnabled)
            } header: {
                Text(tr("Abrufen", "Fetching"))
            } footer: {
                Text(tr("„Manuell“ ruft nur ab, wenn du ⇧⌘N drückst oder auf Aktualisieren klickst.", "“Manually” only checks when you press ⇧⌘N or click Refresh."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(tr("Avatare in der Nachrichtenliste", "Show avatars in the message list"), isOn: $showAvatars)
                Toggle(tr("Externe Inhalte automatisch laden", "Load remote content automatically"), isOn: $loadRemoteContent)
            } header: {
                Text(tr("Darstellung", "Appearance"))
            } footer: {
                Text(tr("Externe Bilder können verraten, wann und wo du eine E-Mail liest.", "Remote images can reveal when and where you read an email."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AccountsSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var clientID = AppSettings.clientID
    @State private var accountToRemove: AccountSession?

    var body: some View {
        Form {
            Section(tr("Konten", "Accounts")) {
                ForEach(model.accounts) { account in
                    HStack(spacing: 10) {
                        AvatarView(name: account.displayName ?? account.email, size: 28)
                        VStack(alignment: .leading) {
                            Text(account.displayName ?? account.email)
                            if account.displayName != nil {
                                Text(account.email).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if account.needsReauth {
                            Button(tr("Erneut anmelden", "Sign In Again")) { Task { await model.signIn(loginHint: account.email) } }
                        }
                        Button(tr("Entfernen", "Remove"), role: .destructive) { accountToRemove = account }
                    }
                }
                Button(tr("Konto hinzufügen …", "Add Account…")) { Task { await model.signIn() } }
                    .disabled(model.isSigningIn)
            }
            Section {
                TextField(tr("Client-ID", "Client ID"), text: $clientID)
                    .onChange(of: clientID) { _, newValue in AppSettings.clientID = newValue }
            } header: {
                Text(tr("Google-OAuth-Client", "Google OAuth client"))
            } footer: {
                Text(tr("Eine neue Client-ID gilt nur für Konten, die du danach hinzufügst.", "A new client ID only applies to accounts you add afterwards."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            tr("\(accountToRemove?.email ?? "") entfernen?", "Remove \(accountToRemove?.email ?? "")?"),
            isPresented: Binding(get: { accountToRemove != nil }, set: { if !$0 { accountToRemove = nil } })
        ) {
            Button(tr("Konto entfernen", "Remove Account"), role: .destructive) {
                if let account = accountToRemove {
                    Task { await model.remove(account) }
                }
            }
        } message: {
            Text(tr("Mailmeg vergisst das Konto und widerruft den Zugriff. Deine E-Mails bleiben in Gmail.", "Mailmeg forgets the account and revokes its access. Your email stays in Gmail."))
        }
    }
}

private struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            Text(AppInfo.name)
                .font(.system(size: 22, weight: .bold))
            Text(AppInfo.versionLine)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Divider().padding(.vertical, 6).frame(width: 260)

            Text(AppInfo.copyright)
                .font(.system(size: 13, weight: .medium))
            VStack(spacing: 4) {
                Text(tr("Kontakt", "Contact"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Link(AppInfo.websiteLabel, destination: AppInfo.website)
                Link(AppInfo.email, destination: URL(string: "mailto:\(AppInfo.email)")!)
            }
            .font(.system(size: 13))
            .tint(Color.accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
    }
}

private struct ComposeSettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppSettings.replyPositionKey) private var replyPosition = AppSettings.ReplyPosition.above.rawValue
    @AppStorage(AppSettings.signatureEnabledKey) private var signatureEnabled = true
    @AppStorage(AppSettings.signatureInRepliesKey) private var signatureInReplies = true

    var body: some View {
        Form {
            Section {
                Picker(tr("Antwort schreiben", "Write replies"), selection: $replyPosition) {
                    Text(tr("Über dem Zitat (wie Gmail)", "Above the quoted message (like Gmail)"))
                        .tag(AppSettings.ReplyPosition.above.rawValue)
                    Text(tr("Unter dem Zitat", "Below the quoted message"))
                        .tag(AppSettings.ReplyPosition.below.rawValue)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text(tr("Antworten", "Replies"))
            }

            Section {
                Toggle(tr("Signatur automatisch einfügen", "Insert signature automatically"), isOn: $signatureEnabled)
                Toggle(tr("Auch bei Antworten und Weiterleitungen", "Also in replies and forwards"), isOn: $signatureInReplies)
                    .disabled(!signatureEnabled)
            } header: {
                Text(tr("Signatur", "Signature"))
            } footer: {
                Text(tr(
                    "Mailmeg verwendet die Signaturen aus Gmail (Einstellungen → Allgemein → Signatur). Beim Wechsel des Absenders wird die passende Signatur eingesetzt.",
                    "Mailmeg uses your Gmail signatures (Settings → General → Signature). Switching the sender inserts the matching signature."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ForEach(model.accounts) { account in
                SenderSection(account: account)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SenderSection: View {
    let account: AccountSession
    @AppStorage private var defaultSender: String

    init(account: AccountSession) {
        self.account = account
        _defaultSender = AppStorage(wrappedValue: "", AppSettings.defaultSenderKey(for: account.id))
    }

    private var selected: SenderIdentity {
        account.identity(for: defaultSender.isEmpty ? nil : defaultSender)
    }

    var body: some View {
        Section {
            Picker(tr("Standard-Absender", "Default sender"), selection: Binding(
                get: { selected.address },
                set: { defaultSender = $0 }
            )) {
                ForEach(account.identities) { identity in
                    Text(identity.label).tag(identity.address)
                }
            }
            let signature = selected.plainSignature
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("Signatur", "Signature"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(signature.isEmpty ? tr("Keine Signatur in Gmail hinterlegt.", "No signature set up in Gmail.") : signature)
                    .font(.system(size: 12))
                    .foregroundStyle(signature.isEmpty ? .secondary : .primary)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
        } header: {
            Text(account.email)
        } footer: {
            if account.identities.count == 1 {
                Text(tr(
                    "Weitere Absenderadressen fügst du in Gmail unter Einstellungen → Konten → „Senden als“ hinzu.",
                    "Add more sender addresses in Gmail under Settings → Accounts → “Send mail as”."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
