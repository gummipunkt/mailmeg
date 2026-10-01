import MailmegKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
            ForEach(model.accounts) { account in
                Section {
                    if account.needsReauth {
                        Button {
                            Task { await model.signIn(loginHint: account.email) }
                        } label: {
                            Label("Sign in again", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(account.systemItems) { item in
                        row(item, account: account)
                    }
                    if !account.userItems.isEmpty {
                        ForEach(account.userItems) { item in
                            row(item, account: account)
                        }
                    }
                } header: {
                    Text(account.email)
                        .contextMenu {
                            Button("Remove Account…", role: .destructive) {
                                Task { await model.remove(account) }
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Mailmeg")
    }

    private func row(_ item: SidebarItem, account: AccountSession) -> some View {
        Label(item.title, systemImage: item.systemImage)
            .padding(.leading, CGFloat(item.indent) * 12)
            .badge(item.unread)
            .tag(Optional(MailboxSelection(accountID: account.id, labelID: item.id)))
    }
}
