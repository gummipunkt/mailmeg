import MailmegKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        List(selection: Binding(
            get: { model.selection },
            set: { newValue in
                DebugLog.log("sidebar selection binding set: \(newValue?.labelID ?? "nil")")
                model.select(newValue)
            }
        )) {
            ForEach(model.accounts) { account in
                Section {
                    if account.needsReauth {
                        Button {
                            Task { await model.signIn(loginHint: account.email) }
                        } label: {
                            Label("Erneut anmelden", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(entries(account.systemItems, of: account), id: \.selection) { entry in
                        row(entry)
                    }
                } header: {
                    AccountHeader(account: account, isDemo: model.isDemo)
                        .contextMenu {
                            Button("Konto entfernen …", role: .destructive) {
                                Task { await model.remove(account) }
                            }
                        }
                }

                let labels = entries(account.userItems, of: account)
                if !labels.isEmpty {
                    Section("Labels") {
                        ForEach(labels, id: \.selection) { entry in
                            row(entry)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
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
        .themedWindowBackground(Theme.sidebar)
    }

    /// Rows are identified by their full selection value. List matches a row's tag
    /// against the selection type, so a plain label ID would make rows unselectable.
    private func entries(_ items: [SidebarItem], of account: AccountSession) -> [SidebarEntry] {
        items.map { SidebarEntry(selection: MailboxSelection(accountID: account.id, labelID: $0.id), item: $0) }
    }

    private func row(_ entry: SidebarEntry) -> some View {
        let item = entry.item
        return Label {
            Text(item.title)
        } icon: {
            Image(systemName: item.systemImage)
                .foregroundStyle(tint(for: item))
        }
        .padding(.leading, CGFloat(item.indent) * 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // The whole row reacts to clicks, independent of List's own selection handling.
        .simultaneousGesture(TapGesture().onEnded {
            DebugLog.log("sidebar row tapped: \(item.id)")
            model.select(entry.selection)
        })
        .badge(item.unread)
        .tag(entry.selection)
        .accessibilityIdentifier("sidebar.\(item.id)")
    }

    private func tint(for item: SidebarItem) -> Color {
        if let hex = item.colorHex { return Color(hex: hex) }
        switch item.id {
        case SystemLabel.inbox, SystemLabel.starred, SystemLabel.important: return .accentColor
        default: return Palette.periwinkle
        }
    }
}

private struct SidebarEntry: Hashable {
    let selection: MailboxSelection
    let item: SidebarItem
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
