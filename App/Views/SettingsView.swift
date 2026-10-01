import MailmegKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
            AccountsSettingsView()
                .tabItem { Label("Konten", systemImage: "person.crop.circle") }
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
                Toggle("Externe Inhalte automatisch laden", isOn: $loadRemoteContent)
            } footer: {
                Text("Externe Bilder können verraten, wann und wo du eine E-Mail liest.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Mitteilungen bei neuen E-Mails", isOn: $notificationsEnabled)
                Picker("Nach neuen E-Mails suchen", selection: $refreshInterval) {
                    Text("Alle 30 Sekunden").tag(30.0)
                    Text("Jede Minute").tag(60.0)
                    Text("Alle 5 Minuten").tag(300.0)
                    Text("Alle 15 Minuten").tag(900.0)
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
            Section("Konten") {
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
                            Button("Erneut anmelden") { Task { await model.signIn(loginHint: account.email) } }
                        }
                        Button("Entfernen", role: .destructive) { accountToRemove = account }
                    }
                }
                Button("Konto hinzufügen …") { Task { await model.signIn() } }
                    .disabled(model.isSigningIn)
            }
            Section {
                TextField("Client-ID", text: $clientID)
                    .onChange(of: clientID) { _, newValue in AppSettings.clientID = newValue }
            } header: {
                Text("Google-OAuth-Client")
            } footer: {
                Text("Eine neue Client-ID gilt nur für Konten, die du danach hinzufügst.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "\(accountToRemove?.email ?? "") entfernen?",
            isPresented: Binding(get: { accountToRemove != nil }, set: { if !$0 { accountToRemove = nil } })
        ) {
            Button("Konto entfernen", role: .destructive) {
                if let account = accountToRemove {
                    Task { await model.remove(account) }
                }
            }
        } message: {
            Text("Mailmeg vergisst das Konto und widerruft den Zugriff. Deine E-Mails bleiben in Gmail.")
        }
    }
}
