import AppKit
import MailmegKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(tr("Allgemein", "General"), systemImage: "gearshape") }
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

    var body: some View {
        Form {
            Section {
                Toggle(tr("Externe Inhalte automatisch laden", "Load remote content automatically"), isOn: $loadRemoteContent)
            } footer: {
                Text(tr("Externe Bilder können verraten, wann und wo du eine E-Mail liest.", "Remote images can reveal when and where you read an email."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(tr("Mitteilungen bei neuen E-Mails", "Notify me about new email"), isOn: $notificationsEnabled)
                Picker(tr("Nach neuen E-Mails suchen", "Check for new email"), selection: $refreshInterval) {
                    Text(tr("Alle 30 Sekunden", "Every 30 seconds")).tag(30.0)
                    Text(tr("Jede Minute", "Every minute")).tag(60.0)
                    Text(tr("Alle 5 Minuten", "Every 5 minutes")).tag(300.0)
                    Text(tr("Alle 15 Minuten", "Every 15 minutes")).tag(900.0)
                }
                .onChange(of: refreshInterval) { model.startPolling() }
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
