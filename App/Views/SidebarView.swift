import MailmegKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List(selection: Binding(get: { model.selection }, set: { model.select($0) })) {
            ForEach(model.accounts) { account in
                Section {
                    if account.needsReauth {
                        Button {
                            Task { await model.signIn(loginHint: account.email) }
                        } label: {
                            Label("Erneut anmelden", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(account.systemItems) { item in
                        row(item, account: account)
                    }
                } header: {
                    AccountHeader(account: account, isDemo: model.isDemo)
                        .contextMenu {
                            Button("Konto entfernen …", role: .destructive) {
                                Task { await model.remove(account) }
                            }
                        }
                }

                let labels = account.userItems
                if !labels.isEmpty {
                    Section("Labels") {
                        ForEach(labels) { item in
                            row(item, account: account)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            Button {
                openWindow(value: model.newDraft())
            } label: {
                Label("Neue E-Mail", systemImage: "square.and.pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .accessibilityIdentifier("compose")
        }
    }

    private func row(_ item: SidebarItem, account: AccountSession) -> some View {
        Label {
            Text(item.title)
        } icon: {
            Image(systemName: item.systemImage)
                .foregroundStyle(tint(for: item))
        }
        .padding(.leading, CGFloat(item.indent) * 14)
        .badge(item.unread)
        .tag(Optional(MailboxSelection(accountID: account.id, labelID: item.id)))
        .accessibilityIdentifier("sidebar.\(item.id)")
    }

    private func tint(for item: SidebarItem) -> Color {
        if let hex = item.colorHex { return Color(hex: hex) }
        switch item.id {
        case SystemLabel.inbox: return .accentColor
        case SystemLabel.starred: return .yellow
        case SystemLabel.important: return .orange
        case SystemLabel.sent: return .teal
        case SystemLabel.draft: return .gray
        case AccountSession.allMailID: return .indigo
        case SystemLabel.spam: return .red
        default: return .secondary
        }
    }
}

private struct AccountHeader: View {
    let account: AccountSession
    let isDemo: Bool

    var body: some View {
        HStack(spacing: 8) {
            AvatarView(name: account.displayName ?? account.email, size: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(account.displayName ?? account.email)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(isDemo ? "Demo-Konto" : account.email)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
}
