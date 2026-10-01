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
    @FocusState private var focusedField: Field?

    private enum Field { case to, cc, bcc, subject, body }

    init(draft: ComposeDraft) {
        _draft = State(initialValue: draft)
        _showsCcBcc = State(initialValue: !draft.cc.isEmpty || !draft.bcc.isEmpty)
    }

    private var account: AccountSession? {
        model.account(id: draft.accountID) ?? model.accounts.first
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if model.accounts.count > 1 {
                    fieldRow("Von") {
                        Picker("Von", selection: $draft.accountID) {
                            ForEach(model.accounts) { account in
                                Text(account.displayName.map { "\($0) <\(account.email)>" } ?? account.email).tag(account.id)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Spacer()
                    }
                }
                fieldRow("An") {
                    TextField("", text: $draft.to, prompt: Text("name@beispiel.de"))
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .to)
                    Button(showsCcBcc ? "Cc/Bcc ausblenden" : "Cc/Bcc") {
                        withAnimation(.snappy(duration: 0.15)) { showsCcBcc.toggle() }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11.5))
                }
                if showsCcBcc {
                    fieldRow("Cc") {
                        TextField("", text: $draft.cc).textFieldStyle(.plain).focused($focusedField, equals: .cc)
                    }
                    fieldRow("Bcc") {
                        TextField("", text: $draft.bcc).textFieldStyle(.plain).focused($focusedField, equals: .bcc)
                    }
                }
                fieldRow("Betreff") {
                    TextField("", text: $draft.subject)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .focused($focusedField, equals: .subject)
                }
            }

            TextEditor(text: $draft.body)
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .focused($focusedField, equals: .body)

            if !attachments.isEmpty || !draft.forwardedAttachments.isEmpty {
                Divider()
                attachmentList
            }
        }
        .background(Theme.cardFill)
        .navigationTitle(draft.subject.isEmpty ? "Neue E-Mail" : draft.subject)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isImporting = true
                } label: {
                    Label("Anhängen", systemImage: "paperclip")
                }
                .help("Dateien anhängen")

                Button {
                    Task { await send() }
                } label: {
                    HStack(spacing: 6) {
                        if isSending {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        Text("Senden")
                    }
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSending || account == nil)
                .help("Senden (⌘↩)")
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            addAttachments(result)
        }
        .alert("E-Mail nicht gesendet", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            if draft.accountID.isEmpty, let first = model.accounts.first {
                draft.accountID = first.id
            }
            focusedField = draft.to.isEmpty ? .to : .body
        }
        .frame(minWidth: 520, minHeight: 400)
    }

    private func fieldRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
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
            Divider().padding(.leading, 16)
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
            .help("Anhang entfernen")
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

    private func send() async {
        guard let account else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await MailSender.send(draft, attachments: attachments, account: account)
            model.didSend(from: account)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
