import MailmegKit
import SwiftUI

/// A Gmail filter the way the editor shows it. What the editor has no control for (forwarding,
/// size limits, categories) is kept from the filter being edited.
struct FilterDraft: Equatable, Identifiable {
    let id = UUID()
    var from = ""
    var to = ""
    var subject = ""
    var hasWords = ""
    var doesntHave = ""
    var hasAttachment = false

    var skipInbox = false
    var markRead = false
    var star = false
    var trash = false
    var neverSpam = false
    var markImportant = false
    /// The label to apply ("" for none).
    var labelID = ""

    /// The filter being edited; nil for a new one.
    var original: GmailFilter?

    private static let managedAdds: Set<String> = [SystemLabel.starred, SystemLabel.trash, SystemLabel.important]
    private static let managedRemoves: Set<String> = [SystemLabel.inbox, SystemLabel.unread, SystemLabel.spam]

    init() {}

    init(_ filter: GmailFilter, userLabelIDs: Set<String>) {
        original = filter
        let criteria = filter.criteria ?? GmailFilter.Criteria()
        from = criteria.from ?? ""
        to = criteria.to ?? ""
        subject = criteria.subject ?? ""
        hasWords = criteria.query ?? ""
        doesntHave = criteria.negatedQuery ?? ""
        hasAttachment = criteria.hasAttachment ?? false

        let adds = filter.action?.addLabelIds ?? []
        let removes = Set(filter.action?.removeLabelIds ?? [])
        star = adds.contains(SystemLabel.starred)
        trash = adds.contains(SystemLabel.trash)
        markImportant = adds.contains(SystemLabel.important)
        labelID = adds.first { userLabelIDs.contains($0) } ?? ""
        labelIDBeforeEditing = labelID
        skipInbox = removes.contains(SystemLabel.inbox)
        markRead = removes.contains(SystemLabel.unread)
        neverSpam = removes.contains(SystemLabel.spam)
    }

    private static func value(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var criteria: GmailFilter.Criteria {
        var result = original?.criteria ?? GmailFilter.Criteria()
        result.from = Self.value(from)
        result.to = Self.value(to)
        result.subject = Self.value(subject)
        result.query = Self.value(hasWords)
        result.negatedQuery = Self.value(doesntHave)
        result.hasAttachment = hasAttachment ? true : nil
        return result
    }

    var action: GmailFilter.Action {
        let previousLabel = labelIDBeforeEditing
        var adds = (original?.action?.addLabelIds ?? []).filter { !Self.managedAdds.contains($0) && $0 != previousLabel }
        if star { adds.append(SystemLabel.starred) }
        if trash { adds.append(SystemLabel.trash) }
        if markImportant { adds.append(SystemLabel.important) }
        if !labelID.isEmpty { adds.append(labelID) }

        var removes = (original?.action?.removeLabelIds ?? []).filter { !Self.managedRemoves.contains($0) }
        if skipInbox { removes.append(SystemLabel.inbox) }
        if markRead { removes.append(SystemLabel.unread) }
        if neverSpam { removes.append(SystemLabel.spam) }

        return GmailFilter.Action(
            addLabelIds: adds.isEmpty ? nil : adds,
            removeLabelIds: removes.isEmpty ? nil : removes,
            forward: original?.action?.forward
        )
    }

    /// The label the edited filter applied when the editor opened.
    private var labelIDBeforeEditing = ""

    var isValid: Bool {
        !criteria.isEmpty && !action.isEmpty
    }
}

/// Settings → Filters: the Gmail filters of an account, to look at, add, change and delete.
/// They live in Gmail itself and apply to new mail, whichever app is open.
struct FilterSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var accountID = ""
    @State private var filters: [GmailFilter] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var errorText: String?
    @State private var needsPermission = false
    @State private var editing: FilterDraft?
    @State private var deleting: GmailFilter?

    private var account: AccountSession? {
        model.accounts.first { $0.id == accountID } ?? model.accounts.first
    }

    private var canEdit: Bool {
        guard let account else { return false }
        return account.canEditFilters && !needsPermission
    }

    var body: some View {
        Form {
            if model.accounts.count > 1 {
                Section {
                    Picker(tr("Konto", "Account"), selection: Binding(get: { account?.id ?? "" }, set: { accountID = $0 })) {
                        ForEach(model.accounts) { account in
                            Text(model.isDemo ? tr("Demo-Konto", "Demo account") : account.email).tag(account.id)
                        }
                    }
                }
            }

            if let account, !canEdit {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr(
                            "Um Filter anzulegen, zu ändern oder zu löschen, braucht MailMeG einmalig eine weitere Google-Berechtigung („Gmail-Einstellungen und Filter verwalten“). Ansehen kannst du deine Filter auch ohne sie.",
                            "To create, change or delete filters, MailMeG needs one more Google permission once (“manage your Gmail settings and filters”). You can look at your filters without it."
                        ))
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        Button(tr("Berechtigung erteilen …", "Grant Permission…")) {
                            Task {
                                await model.signIn(loginHint: account.email)
                                needsPermission = false
                                await load()
                            }
                        }
                        .accessibilityIdentifier("filters.grant")
                    }
                    .padding(.vertical, 2)
                }
            }

            Section {
                if isLoading && !hasLoaded {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(tr("Filter werden geladen …", "Loading filters…"))
                            .foregroundStyle(.secondary)
                    }
                } else if filters.isEmpty {
                    Text(tr("Für dieses Konto gibt es noch keine Filter.", "This account has no filters yet."))
                        .foregroundStyle(.secondary)
                }
                ForEach(filters) { filter in
                    row(filter)
                }
                Button {
                    editing = FilterDraft()
                } label: {
                    Label(tr("Neuer Filter …", "New Filter…"), systemImage: "plus")
                }
                .disabled(!canEdit)
                .accessibilityIdentifier("filters.new")
            } header: {
                Text(tr("Gmail-Filter", "Gmail filters"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let errorText {
                        Text(errorText)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(tr(
                        "Die Filter liegen in Gmail und gelten für neu eintreffende E-Mails – auch wenn MailMeG nicht läuft. Änderungen sind sofort in Gmail sichtbar.",
                        "Filters live in Gmail and apply to newly arriving email – even when MailMeG is not running. Changes show up in Gmail at once."
                    ))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 380)
        .task(id: account?.id) { await load() }
        .sheet(item: $editing) { draft in
            FilterEditor(draft: draft, labels: userLabels) { edited in
                Task { await save(edited) }
            }
        }
        .confirmationDialog(
            tr("Diesen Filter löschen?", "Delete this filter?"),
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button(tr("Löschen", "Delete"), role: .destructive) {
                if let filter = deleting { Task { await delete(filter) } }
            }
            Button(tr("Abbrechen", "Cancel"), role: .cancel) {}
        } message: {
            Text(tr("Der Filter wird auch in Gmail gelöscht. Bereits einsortierte E-Mails bleiben, wo sie sind.", "The filter is removed from Gmail, too. Email it already filed stays where it is."))
        }
    }

    private var userLabels: [GmailLabel] {
        (account?.labels ?? [])
            .filter { !$0.isSystem }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func row(_ filter: GmailFilter) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(criteriaText(filter))
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(actionText(filter))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button {
                editing = FilterDraft(filter, userLabelIDs: Set(userLabels.map(\.id)))
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .disabled(!canEdit)
            .help(tr("Filter bearbeiten", "Edit filter"))
            .accessibilityLabel(tr("Filter bearbeiten", "Edit filter"))
            Button {
                deleting = filter
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(!canEdit)
            .help(tr("Filter löschen", "Delete filter"))
            .accessibilityLabel(tr("Filter löschen", "Delete filter"))
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filter.\(filter.id)")
    }

    // MARK: Describing a filter

    private func criteriaText(_ filter: GmailFilter) -> String {
        let criteria = filter.criteria ?? GmailFilter.Criteria()
        var parts: [String] = []
        if let from = criteria.from { parts.append(tr("Von: \(from)", "From: \(from)")) }
        if let to = criteria.to { parts.append(tr("An: \(to)", "To: \(to)")) }
        if let subject = criteria.subject { parts.append(tr("Betreff: \(subject)", "Subject: \(subject)")) }
        if let query = criteria.query { parts.append(tr("Enthält: \(query)", "Has: \(query)")) }
        if let negated = criteria.negatedQuery { parts.append(tr("Enthält nicht: \(negated)", "Doesn’t have: \(negated)")) }
        if criteria.hasAttachment == true { parts.append(tr("Mit Anhang", "Has attachment")) }
        if let size = criteria.size {
            let bytes = Formatting.byteCount(size)
            parts.append(criteria.sizeComparison == "smaller" ? tr("Kleiner als \(bytes)", "Smaller than \(bytes)") : tr("Größer als \(bytes)", "Larger than \(bytes)"))
        }
        return parts.isEmpty ? tr("Alle E-Mails", "All email") : parts.joined(separator: " · ")
    }

    private func labelName(_ id: String) -> String {
        guard let label = account?.label(id: id) else { return id }
        if id.hasPrefix("CATEGORY_") {
            return tr("Kategorie \(label.name.replacingOccurrences(of: "CATEGORY_", with: "").capitalized)", "Category \(label.name.replacingOccurrences(of: "CATEGORY_", with: "").capitalized)")
        }
        return label.name
    }

    private func actionText(_ filter: GmailFilter) -> String {
        let adds = filter.action?.addLabelIds ?? []
        let removes = filter.action?.removeLabelIds ?? []
        var parts: [String] = []
        if removes.contains(SystemLabel.inbox) { parts.append(tr("Posteingang überspringen", "Skip the inbox")) }
        if removes.contains(SystemLabel.unread) { parts.append(tr("Als gelesen markieren", "Mark as read")) }
        if adds.contains(SystemLabel.starred) { parts.append(tr("Markieren", "Star")) }
        for id in adds where ![SystemLabel.starred, SystemLabel.trash, SystemLabel.important].contains(id) {
            parts.append(tr("Label „\(labelName(id))“", "Label “\(labelName(id))”"))
        }
        if adds.contains(SystemLabel.trash) { parts.append(tr("Löschen", "Delete")) }
        if removes.contains(SystemLabel.spam) { parts.append(tr("Nie als Spam", "Never spam")) }
        if adds.contains(SystemLabel.important) { parts.append(tr("Als wichtig markieren", "Mark as important")) }
        if removes.contains(SystemLabel.important) { parts.append(tr("Nie als wichtig", "Never important")) }
        if let forward = filter.action?.forward, !forward.isEmpty { parts.append(tr("Weiterleiten an \(forward)", "Forward to \(forward)")) }
        return parts.isEmpty ? tr("Keine Aktion", "No action") : parts.joined(separator: " · ")
    }

    // MARK: Gmail

    private func load() async {
        guard let account else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            filters = try await account.client.listFilters()
            hasLoaded = true
            errorText = nil
        } catch {
            show(error)
        }
    }

    private func save(_ edited: FilterDraft) async {
        guard let account else { return }
        do {
            _ = try await account.client.createFilter(criteria: edited.criteria, action: edited.action)
            // Gmail cannot change a filter: the new one replaces the old.
            if let old = edited.original {
                try await account.client.deleteFilter(id: old.id)
            }
            errorText = nil
        } catch {
            show(error)
        }
        await load()
    }

    private func delete(_ filter: GmailFilter) async {
        guard let account else { return }
        do {
            try await account.client.deleteFilter(id: filter.id)
            errorText = nil
        } catch {
            show(error)
        }
        await load()
    }

    private func show(_ error: Error) {
        if let api = error as? GmailAPIError, api.isInsufficientScope {
            needsPermission = true
            errorText = nil
        } else {
            errorText = error.localizedDescription
        }
    }
}

/// The sheet for a new or changed filter.
private struct FilterEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: FilterDraft
    let labels: [GmailLabel]
    let onSave: (FilterDraft) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(tr("Wenn eine E-Mail eintrifft …", "When an email arrives…")) {
                    TextField(tr("Von", "From"), text: $draft.from, prompt: Text("anna@example.com"))
                        .accessibilityIdentifier("filter.from")
                    TextField(tr("An", "To"), text: $draft.to)
                    TextField(tr("Betreff enthält", "Subject contains"), text: $draft.subject)
                        .accessibilityIdentifier("filter.subject")
                    TextField(tr("Enthält die Wörter", "Has the words"), text: $draft.hasWords)
                    TextField(tr("Enthält nicht", "Doesn’t have"), text: $draft.doesntHave)
                    Toggle(tr("Hat einen Anhang", "Has an attachment"), isOn: $draft.hasAttachment)
                }
                Section(tr("… dann", "…then")) {
                    Toggle(tr("Posteingang überspringen (archivieren)", "Skip the inbox (archive it)"), isOn: $draft.skipInbox)
                        .accessibilityIdentifier("filter.skipInbox")
                    Toggle(tr("Als gelesen markieren", "Mark as read"), isOn: $draft.markRead)
                    Toggle(tr("Markieren (Stern)", "Star it"), isOn: $draft.star)
                    Picker(tr("Label zuweisen", "Apply the label"), selection: $draft.labelID) {
                        Text(tr("Keines", "None")).tag("")
                        ForEach(labels) { label in
                            Text(label.name).tag(label.id)
                        }
                    }
                    Toggle(tr("Als wichtig markieren", "Mark as important"), isOn: $draft.markImportant)
                    Toggle(tr("Nie als Spam einstufen", "Never send it to Spam"), isOn: $draft.neverSpam)
                    Toggle(tr("Löschen", "Delete it"), isOn: $draft.trash)
                }
            }
            .formStyle(.grouped)

            HStack {
                if !draft.isValid {
                    Text(tr("Mindestens eine Bedingung und eine Aktion wählen.", "Choose at least one condition and one action."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(tr("Abbrechen", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(draft.original == nil ? tr("Filter anlegen", "Create Filter") : tr("Sichern", "Save")) {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid)
                .accessibilityIdentifier("filter.save")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 480, height: 560)
    }
}
