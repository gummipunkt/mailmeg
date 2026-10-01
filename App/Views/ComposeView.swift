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

    private enum Field { case to, subject, body }

    init(draft: ComposeDraft) {
        _draft = State(initialValue: draft)
        _showsCcBcc = State(initialValue: !draft.cc.isEmpty || !draft.bcc.isEmpty)
    }

    private var account: AccountSession? {
        model.account(id: draft.accountID) ?? model.accounts.first
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if model.accounts.count > 1 {
                    Picker("From:", selection: $draft.accountID) {
                        ForEach(model.accounts) { account in
                            Text(account.email).tag(account.id)
                        }
                    }
                }
                HStack {
                    TextField("To:", text: $draft.to, prompt: Text("name@example.com"))
                        .focused($focusedField, equals: .to)
                    Button(showsCcBcc ? "Hide Cc/Bcc" : "Cc/Bcc") { showsCcBcc.toggle() }
                        .buttonStyle(.link)
                }
                if showsCcBcc {
                    TextField("Cc:", text: $draft.cc)
                    TextField("Bcc:", text: $draft.bcc)
                }
                TextField("Subject:", text: $draft.subject)
                    .focused($focusedField, equals: .subject)
            }
            .formStyle(.columns)
            .padding()

            Divider()

            TextEditor(text: $draft.body)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .focused($focusedField, equals: .body)

            if !attachments.isEmpty || !draft.forwardedAttachments.isEmpty {
                Divider()
                attachmentList
            }
        }
        .navigationTitle(draft.subject.isEmpty ? String(localized: "New Message") : draft.subject)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    isImporting = true
                } label: {
                    Label("Attach", systemImage: "paperclip")
                }
                .help("Attach Files")

                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Send", systemImage: "paperplane.fill")
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSending || account == nil)
                .help("Send (⌘↩)")
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            addAttachments(result)
        }
        .alert("Message Not Sent", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
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
        .frame(minWidth: 480, minHeight: 360)
    }

    private var attachmentList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
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
            .padding(10)
        }
    }

    private func chip(name: String, size: Int, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "doc")
            Text(name).lineLimit(1)
            Text(Formatting.byteCount(size)).foregroundStyle(.secondary)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
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
        let to = EmailAddress.parseList(draft.to)
        let cc = EmailAddress.parseList(draft.cc)
        let bcc = EmailAddress.parseList(draft.bcc)
        guard !(to + cc + bcc).isEmpty else {
            errorMessage = String(localized: "Please add at least one recipient.")
            return
        }
        if let invalid = (to + cc + bcc).first(where: { !$0.address.contains("@") }) {
            errorMessage = String(localized: "“\(invalid.address)” is not a valid email address.")
            return
        }

        isSending = true
        defer { isSending = false }
        do {
            var allAttachments = attachments
            for forwarded in draft.forwardedAttachments {
                let data: Data
                if let inline = forwarded.inlineData {
                    data = inline
                } else if let attachmentID = forwarded.attachmentID {
                    data = try await account.client.attachment(messageID: forwarded.messageID, attachmentID: attachmentID)
                } else {
                    continue
                }
                allAttachments.append(OutgoingAttachment(filename: forwarded.filename, mimeType: forwarded.mimeType, data: data))
            }

            let message = OutgoingMessage(
                from: account.sender,
                to: to,
                cc: cc,
                bcc: bcc,
                subject: draft.subject,
                textBody: draft.body,
                inReplyTo: draft.inReplyTo,
                references: draft.references,
                attachments: allAttachments
            )
            let raw = MIMEBuilder().build(message)
            try await account.client.send(rfc822: raw, threadID: draft.threadID)
            model.didSend(from: account)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
