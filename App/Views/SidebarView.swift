import MailmegKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

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
                            Label(tr("Erneut anmelden", "Sign In Again"), systemImage: "exclamationmark.triangle.fill")
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
                            Button(tr("Konto entfernen …", "Remove Account…"), role: .destructive) {
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
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .glassBackground(.sidebar)
    }

    /// Fetch status and quick access to refresh and settings, at the foot of the sidebar.
    private var footer: some View {
        HStack(spacing: 8) {
            if model.isRefreshing {
                ProgressView().controlSize(.mini)
            }
            Text(fetchStatus)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("sidebar.lastRefresh")
            Spacer(minLength: 4)
            IconButton(systemImage: "arrow.clockwise", help: tr("Neue E-Mails abrufen (⇧⌘N)", "Get New Mail (⇧⌘N)")) {
                Task { await model.refreshAll() }
            }
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(tr("Einstellungen", "Settings"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }

    private var fetchStatus: String {
        if model.isRefreshing { return tr("Wird abgerufen …", "Fetching…") }
        guard let date = model.lastRefresh else { return "" }
        let time = date.formatted(date: .omitted, time: .shortened)
        return tr("Abgerufen \(time)", "Fetched \(time)")
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
                Text(isDemo ? tr("Demo-Konto", "Demo account") : account.email)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
}
