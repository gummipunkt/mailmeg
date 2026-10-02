import AppKit
import MailmegKit
import SwiftUI
import UniformTypeIdentifiers

/// Identifies a message whose source or headers should be shown in their own window.
struct SourceRequest: Codable, Hashable {
    enum Mode: String, Codable { case headers, source }
    var accountID: String
    var messageID: String
    var subject: String
    var mode: Mode
}

/// Shows the original message (RFC 822 source) or its full header list.
struct SourceView: View {
    @Environment(AppModel.self) private var model
    let request: SourceRequest
    @State private var mode: SourceRequest.Mode
    @State private var source: String?
    @State private var data: Data?
    @State private var error: String?

    init(request: SourceRequest) {
        self.request = request
        _mode = State(initialValue: request.mode)
    }

    private var headers: [IndexedHeader] {
        RawMessage.headers(from: source ?? "").enumerated().map { IndexedHeader(id: $0.offset, header: $0.element) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("", selection: $mode) {
                    Text(tr("Header", "Headers")).tag(SourceRequest.Mode.headers)
                    Text(tr("Quelltext", "Source")).tag(SourceRequest.Mode.source)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("source.mode")
                Spacer()
                Button {
                    copy()
                } label: {
                    Label(tr("Kopieren", "Copy"), systemImage: "doc.on.doc")
                }
                .disabled(source == nil)
                Button {
                    save()
                } label: {
                    Label(tr("Sichern …", "Save…"), systemImage: "square.and.arrow.down")
                }
                .disabled(data == nil)
            }
            .padding(12)
            Divider()

            Group {
                if let error {
                    ContentUnavailableView(tr("Quelltext nicht verfügbar", "Source Unavailable"), systemImage: "exclamationmark.triangle", description: Text(error))
                } else if source == nil {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if mode == .headers {
                    Table(headers) {
                        TableColumn(tr("Feld", "Field")) { row in
                            Text(row.header.name)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .width(min: 120, ideal: 170, max: 260)
                        TableColumn(tr("Wert", "Value")) { row in
                            Text(row.header.value)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityIdentifier("source.headers")
                } else {
                    ReadOnlyTextView(text: source ?? "")
                        .accessibilityIdentifier("source.text")
                }
            }
        }
        .frame(minWidth: 560, minHeight: 380)
        .navigationTitle(request.subject.isEmpty ? tr("Quelltext", "Source") : request.subject)
        .task { await load() }
    }

    private func load() async {
        guard let account = model.account(id: request.accountID) else {
            error = tr("Das Konto ist nicht mehr angemeldet.", "The account is no longer signed in.")
            return
        }
        do {
            let raw = try await account.client.rawMessage(id: request.messageID)
            data = raw
            source = RawMessage.text(from: raw)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func copy() {
        let text = mode == .headers
            ? headers.map { "\($0.header.name): \($0.header.value)" }.joined(separator: "\n")
            : (source ?? "")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func save() {
        guard let data else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "eml") ?? .data]
        let base = request.subject.isEmpty ? "message" : request.subject
        panel.nameFieldStringValue = base.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".eml"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url, options: .atomic)
    }
}

private struct IndexedHeader: Identifiable {
    let id: Int
    let header: MessageHeader
}

/// Fast, selectable monospaced text for large message sources.
struct ReadOnlyTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.string = text
        textView.setAccessibilityIdentifier("source.text")
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
    }
}
