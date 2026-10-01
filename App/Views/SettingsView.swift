import MailmegKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            AccountsSettingsView()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
        }
        .frame(width: 520)
        .padding()
    }
}

private struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppSettings.loadRemoteContentKey) private var loadRemoteContent = false
    @AppStorage(AppSettings.notificationsKey) private var notificationsEnabled = true
    @AppStorage(AppSettings.refreshIntervalKey) private var refreshInterval: Double = 60

    var body: some View {
        Form {
            Toggle("Load remote content in messages automatically", isOn: $loadRemoteContent)
            Text("Remote images can be used to track when and where you read an email.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Show notifications for new mail", isOn: $notificationsEnabled)
            Picker("Check for new mail", selection: $refreshInterval) {
                Text("Every 30 seconds").tag(30.0)
                Text("Every minute").tag(60.0)
                Text("Every 5 minutes").tag(300.0)
                Text("Every 15 minutes").tag(900.0)
            }
            .onChange(of: refreshInterval) { model.startPolling() }
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
            Section("Accounts") {
                ForEach(model.accounts) { account in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(account.displayName ?? account.email)
                            if account.displayName != nil {
                                Text(account.email).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if account.needsReauth {
                            Button("Sign In Again") { Task { await model.signIn(loginHint: account.email) } }
                        }
                        Button("Remove", role: .destructive) { accountToRemove = account }
                    }
                }
                Button("Add Account…") { Task { await model.signIn() } }
                    .disabled(model.isSigningIn)
            }
            Section {
                TextField("Client ID", text: $clientID)
                    .onSubmit { AppSettings.clientID = clientID }
                    .onChange(of: clientID) { _, newValue in AppSettings.clientID = newValue }
            } header: {
                Text("Google OAuth Client")
            } footer: {
                Text("Changing the client ID only affects accounts you add afterwards.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Remove \(accountToRemove?.email ?? "")?",
            isPresented: Binding(get: { accountToRemove != nil }, set: { if !$0 { accountToRemove = nil } })
        ) {
            Button("Remove Account", role: .destructive) {
                if let account = accountToRemove {
                    Task { await model.remove(account) }
                }
            }
        } message: {
            Text("Mailmeg will forget the account and revoke its access. Your mail stays in Gmail.")
        }
    }
}
