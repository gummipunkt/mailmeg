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
        .safeAreaInset(edge: .top, spacing: 0) {
            SectionSwitch()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                TodayAgendaView()
                SidebarFooter()
            }
        }
        .glassBackground(.sidebar)
    }

    /// Rows are identified by their full selection value. List matches a row's tag
    /// against the selection type, so a plain label ID would make rows unselectable.
    private func entries(_ items: [SidebarItem], of account: AccountSession) -> [SidebarEntry] {
        items.map { SidebarEntry(selection: MailboxSelection(accountID: account.id, labelID: $0.id), item: $0) }
    }

    private func row(_ entry: SidebarEntry) -> some View {
        let item = entry.item
        let isSelected = model.selection == entry.selection
        let color = tint(for: item)
        return HStack(spacing: 9) {
            // Every folder has its own colour, on a pastel tile.
            Image(systemName: item.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6.5, style: .continuous).fill(color.opacity(0.17)))
            Text(item.title)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 4)
            if item.unread > 0 {
                Text("\(item.unread)")
                    .font(.system(size: 10.5, weight: .bold).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white : color)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 18)
                    .background(Capsule().fill(isSelected ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(color.opacity(0.15))))
            }
        }
        .padding(.leading, CGFloat(item.indent) * 14)
        .padding(.vertical, -1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // The whole row reacts to clicks, independent of List's own selection handling.
        .simultaneousGesture(TapGesture().onEnded {
            DebugLog.log("sidebar row tapped: \(item.id)")
            model.select(entry.selection)
        })
        .tag(entry.selection)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.unread > 0 ? "\(item.unread)" : "")
        .accessibilityIdentifier("sidebar.\(item.id)")
        // The selected mailbox is a white pill instead of the system's grey highlight.
        .listRowBackground(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Theme.cardFill.opacity(0.92) : Color.clear)
                .shadow(color: Theme.shadow.opacity(isSelected ? 0.12 : 0), radius: 5, y: 2)
                .padding(.horizontal, 8)
        )
        .background(ListHighlightRemover().frame(width: 0, height: 0))
    }

    private func tint(for item: SidebarItem) -> Color {
        if let hex = item.colorHex { return Color(hex: hex) }
        switch item.id {
        case SystemLabel.inbox: return Palette.violet
        case SystemLabel.starred: return Color(hex: "#F2A900")
        case SystemLabel.important: return Color(hex: "#F2784B")
        case SystemLabel.sent: return Color(hex: "#3B9BF5")
        case SystemLabel.draft: return Color(hex: "#E7689A")
        case AccountSession.allMailID: return Color(hex: "#2BB5A3")
        case SystemLabel.spam: return Color(hex: "#E5534B")
        case SystemLabel.trash: return Color(hex: "#7B839A")
        default: return Palette.periwinkle
        }
    }
}

/// Mail and Calendar as two tabs at the top of the sidebar.
struct SectionSwitch: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 2) {
            tab(.mail, title: tr("Mail", "Mail"), systemImage: "envelope", badge: model.totalInboxUnread, identifier: "section.mail")
            tab(.calendar, title: tr("Kalender", "Calendar"), systemImage: "calendar", badge: 0, identifier: "section.calendar")
        }
        .padding(3)
        .background(Capsule().fill(Palette.violet.opacity(0.1)))
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func tab(_ section: AppSection, title: String, systemImage: String, badge: Int, identifier: String) -> some View {
        let selected = model.section == section
        return Button {
            withAnimation(.snappy(duration: 0.18)) { model.show(section) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                if badge > 0 {
                    Text(badge > 999 ? "999+" : "\(badge)")
                        .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 16, minHeight: 15)
                        .background(Capsule().fill(Color.accentColor.opacity(0.16)))
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background {
                if selected {
                    Capsule()
                        .fill(Theme.cardFill)
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(selected ? "selected" : "")
        .help(section == .mail ? tr("Mail (⌘1)", "Mail (⌘1)") : tr("Kalender (⌘2)", "Calendar (⌘2)"))
    }
}

/// Fetch status and quick access to refresh and settings, at the foot of the sidebar.
struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
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
