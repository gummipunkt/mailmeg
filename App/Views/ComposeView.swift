import AppKit
import MailmegKit
import SwiftUI
import UniformTypeIdentifiers

struct ComposeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ComposeDraft
    @State private var attachments: [OutgoingAttachment] = []
    @State private var showsCcBcc: Bool
    @State private var isSending = false
    @State private var isImporting = false
    @State private var errorMessage: String?
    @State private var autosaver: DraftAutosaver
    @State private var confirmsDiscard = false
    @State private var formatter = RichTextController()
    @FocusState private var focusedField: Field?

    private enum Field { case to, cc, bcc, subject, body }

    init(draft: ComposeDraft) {
        _draft = State(initialValue: draft)
        _autosaver = State(initialValue: DraftAutosaver(draft: draft))
        _showsCcBcc = State(initialValue: !draft.cc.isEmpty || !draft.bcc.isEmpty)
    }

    /// The selected sender; switching it also swaps the signature in the body.
    private var senderSelection: Binding<String> {
        Binding(
            get: { self.account?.identity(for: draft.fromAddress).id ?? "" },
            set: { newID in
                guard let identity = model.allIdentities.first(where: { $0.id == newID }) else { return }
                draft.accountID = identity.accountID
                draft.fromAddress = identity.address
                DraftComposer.swapSignature(in: &draft, to: identity)
            }
        )
    }

    private var account: AccountSession? {
        model.account(id: draft.accountID) ?? model.accounts.first
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header fields
            VStack(spacing: 0) {
                if model.allIdentities.count > 1 {
                    fieldRow(tr("Von", "From")) {
                        Picker(tr("Von", "From"), selection: senderSelection) {
                            ForEach(model.accounts) { account in
                                Section(account.email) {
                                    ForEach(account.identities) { identity in
                                        Text(identity.label).tag(identity.id)
                                    }
                                }
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityIdentifier("compose.from")
                        Spacer()
                    }
                }
                fieldRow(tr("An", "To")) {
                    TextField("", text: $draft.to, prompt: Text(tr("name@beispiel.de", "name@example.com")))
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .to)
                    Button(showsCcBcc ? tr("Cc/Bcc ausblenden", "Hide Cc/Bcc") : "Cc/Bcc") {
                        withAnimation(.snappy(duration: 0.15)) { showsCcBcc.toggle() }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 11.5, weight: .medium))
                }
                if showsCcBcc {
                    fieldRow("Cc") {
                        TextField("", text: $draft.cc).textFieldStyle(.plain).focused($focusedField, equals: .cc)
                    }
                    fieldRow("Bcc") {
                        TextField("", text: $draft.bcc).textFieldStyle(.plain).focused($focusedField, equals: .bcc)
                    }
                }
                fieldRow(tr("Betreff", "Subject"), showsDivider: false) {
                    TextField("", text: $draft.subject, prompt: Text(tr("Worum geht es?", "What’s it about?")))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .focused($focusedField, equals: .subject)
                        .accessibilityIdentifier("compose.subject")
                }
            }
            .card()

            // Body and attachments
            VStack(spacing: 0) {
                FormatBar(controller: formatter)
                Divider().overlay(Theme.hairline.opacity(0.5))
                MailBodyEditor(
                    text: $draft.body,
                    runs: $draft.richBody,
                    initialCursor: draft.cursorOffset,
                    focusOnAppear: !draft.to.isEmpty,
                    controller: formatter
                )
                .padding(.horizontal, 2)

                if !attachments.isEmpty || !draft.forwardedAttachments.isEmpty {
                    Divider().overlay(Theme.hairline.opacity(0.5))
                    attachmentList
                }
            }
            .card()

            // Actions
            HStack(spacing: 10) {
                Button {
                    isImporting = true
                } label: {
                    Label(tr("Anhängen", "Attach"), systemImage: "paperclip")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.tint, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help(tr("Dateien anhängen", "Attach files"))

                IconButton(systemImage: "trash", help: tr("Entwurf verwerfen", "Discard draft")) {
                    confirmsDiscard = true
                }
                .accessibilityIdentifier("compose.discard")

                Button {
                    Task { await saveDraft() }
                } label: {
                    Text(statusText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(autosaver.status == .failed ? Color.red : Color.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("s")
                .help(tr("Entwurf sichern (⌘S)", "Save draft (⌘S)"))
                .accessibilityIdentifier("compose.status")

                Spacer()

                Button {
                    Task { await send() }
                } label: {
                    HStack(spacing: 7) {
                        if isSending {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text(tr("Senden", "Send"))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(colors: [Palette.periwinkle, Palette.violet], startPoint: .top, endPoint: .bottom),
                        in: Capsule()
                    )
                    .shadow(color: Palette.violet.opacity(0.35), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSending || account == nil)
                .opacity(isSending || account == nil ? 0.6 : 1)
                .help(tr("Senden (⌘↩)", "Send (⌘↩)"))
                .accessibilityIdentifier("compose.send")
            }
        }
        .padding(14)
        .glassBackground(.canvas)
        .navigationTitle(draft.subject.isEmpty ? tr("Neue E-Mail", "New Message") : draft.subject)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            addAttachments(result)
        }
        .alert(tr("E-Mail nicht gesendet", "Message Not Sent"), isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: draft) { _, newValue in
            autosaver.schedule(newValue, attachments: attachments, account: account)
        }
        .onChange(of: attachments) { _, newValue in
            autosaver.schedule(draft, attachments: newValue, account: account)
        }
        .onChange(of: autosaver.status) { _, status in
            if case .saved = status, let account { model.draftsChanged(account) }
        }
        .onDisappear {
            // Closing the window keeps the message as a Gmail draft, like Gmail does.
            let snapshot = draft, files = attachments, owner = self.account
            Task { await autosaver.save(snapshot, attachments: files, account: owner) }
        }
        .confirmationDialog(
            tr("Entwurf verwerfen?", "Discard this draft?"),
            isPresented: $confirmsDiscard
        ) {
            Button(tr("Verwerfen", "Discard"), role: .destructive) {
                Task {
                    await autosaver.discard(account: account)
                    if let account { model.draftsChanged(account) }
                    dismiss()
                }
            }
        } message: {
            Text(tr("Die E-Mail wird nicht gesendet und auch in Gmail gelöscht.", "The message won’t be sent and is also removed from Gmail."))
        }
        .onAppear {
            if draft.accountID.isEmpty, let first = model.accounts.first {
                draft.accountID = first.id
            }
            if draft.fromAddress == nil, let account {
                draft.fromAddress = account.defaultIdentity.address
            }
            if draft.to.isEmpty {
                focusedField = .to
            }
        }
        .frame(minWidth: 520, minHeight: 400)
    }

    private func fieldRow<Content: View>(_ title: String, showsDivider: Bool = true, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .trailing)
                content()
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            if showsDivider {
                Divider().overlay(Theme.hairline.opacity(0.5)).padding(.leading, 16)
            }
        }
    }

    private var attachmentList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                    chip(name: attachment.filename, size: attachment.data.count) {
                        attachments.remove(at: index)
                    }
                }
                ForEach(draft.forwardedAttachments) { attachment in
                    chip(name: attachment.filename, size: attachment.size) {
                        draft.forwardedAttachments.removeAll { $0.id == attachment.id }
                    }
                }
            }
            .padding(12)
        }
    }

    private func chip(name: String, size: Int, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.fill")
                .foregroundStyle(Color.accentColor)
            Text(name).lineLimit(1)
            Text(Formatting.byteCount(size)).foregroundStyle(.secondary)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(tr("Anhang entfernen", "Remove attachment"))
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.tint, in: Capsule())
    }

    private func addAttachments(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
                    attachments.append(OutgoingAttachment(filename: url.lastPathComponent, mimeType: mimeType, data: data))
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private var statusText: String {
        switch autosaver.status {
        case .idle:
            return autosaver.draftID == nil ? "" : tr("Entwurf", "Draft")
        case .saving:
            return tr("Wird gesichert …", "Saving…")
        case .saved(let date):
            return tr("Entwurf gesichert · \(date.formatted(date: .omitted, time: .shortened))", "Draft saved · \(date.formatted(date: .omitted, time: .shortened))")
        case .failed:
            return tr("Entwurf nicht gesichert", "Draft not saved")
        }
    }

    private func saveDraft() async {
        await autosaver.save(draft, attachments: attachments, account: account)
    }

    private func send() async {
        guard let account else { return }
        isSending = true
        defer { isSending = false }
        await autosaver.finish()
        var final = draft
        final.gmailDraftID = autosaver.draftID
        do {
            try await MailSender.send(final, attachments: attachments, account: account)
            model.didSend(from: account)
            model.draftsChanged(account)
            dismiss()
        } catch {
            autosaver.resume()
            errorMessage = error.localizedDescription
        }
    }
}
