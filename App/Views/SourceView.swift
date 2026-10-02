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

    @State private var filter = ""

    private var visibleHeaders: [IndexedHeader] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return headers }
        return headers.filter { $0.header.name.localizedCaseInsensitiveContains(query) || $0.header.value.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ModeSwitch(mode: $mode)
                    .accessibilityIdentifier("source.mode")
                if mode == .headers {
                    SearchField(text: $filter, prompt: tr("Header filtern", "Filter headers"), identifier: "source.filter") {}
                        .frame(maxWidth: 260)
                }
                Spacer(minLength: 8)
                GlassCircleButton(systemImage: "doc.on.doc", help: tr("Kopieren", "Copy")) { copy() }
                    .disabled(source == nil)
                    .accessibilityIdentifier("source.copy")
                GlassCircleButton(systemImage: "square.and.arrow.down", help: tr("Als .eml sichern …", "Save as .eml…")) { save() }
                    .disabled(data == nil)
                    .accessibilityIdentifier("source.save")
            }

            Group {
                if let error {
                    ContentUnavailableView(tr("Quelltext nicht verfügbar", "Source Unavailable"), systemImage: "exclamationmark.triangle", description: Text(error))
                } else if source == nil {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if mode == .headers {
                    headerList
                } else {
                    ReadOnlyTextView(text: source ?? "")
                        .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card()

            if source != nil, error == nil {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
        .padding(14)
        .glassBackground(.canvas)
        .frame(minWidth: 560, minHeight: 380)
        .navigationTitle(request.subject.isEmpty ? tr("Quelltext", "Source") : request.subject)
        .task { await load() }
    }

    private var headerList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(visibleHeaders) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(row.header.name)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Self.keyHeaders.contains(row.header.name.lowercased()) ? Color.accentColor : Color.secondary)
                            .frame(width: 170, alignment: .trailing)
                            .lineLimit(2)
                        Text(row.header.value)
                            .font(.system(size: 12, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(row.id.isMultiple(of: 2) ? Color.clear : Theme.tint.opacity(0.35))
                }
                if visibleHeaders.isEmpty {
                    Text(tr("Kein Header passt zu „\(filter)“.", "No header matches “\(filter)”."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .padding(14)
                }
            }
            .padding(.vertical, 6)
        }
        .accessibilityIdentifier("source.headers")
    }

    /// Headers that matter most when checking where a message came from.
    private static let keyHeaders: Set<String> = ["from", "to", "cc", "subject", "date", "delivered-to", "reply-to", "return-path", "authentication-results"]

    private var footer: String {
        let size = Formatting.byteCount(data?.count ?? 0)
        let count = headers.count
        return tr("\(count) Header · \(size) · Original, wie es bei Gmail liegt", "\(count) headers · \(size) · original as stored by Gmail")
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

/// Two-option pill switch in the app's style.
private struct ModeSwitch: View {
    @Binding var mode: SourceRequest.Mode

    var body: some View {
        HStack(spacing: 2) {
            option(.headers, title: tr("Header", "Headers"), systemImage: "list.bullet.rectangle")
            option(.source, title: tr("Quelltext", "Source"), systemImage: "chevron.left.forwardslash.chevron.right")
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.8))
    }

    private func option(_ value: SourceRequest.Mode, title: String, systemImage: String) -> some View {
        let selected = mode == value
        return Button {
            withAnimation(.snappy(duration: 0.18)) { mode = value }
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.75))
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background {
                    if selected {
                        Capsule().fill(LinearGradient(colors: [Palette.periwinkle, Palette.violet], startPoint: .top, endPoint: .bottom))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Fast, selectable monospaced text for large message sources; header names are tinted.
struct ReadOnlyTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.textStorage?.setAttributedString(Self.styled(text))
        textView.setAccessibilityIdentifier("source.text")
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.textStorage?.setAttributedString(Self.styled(text))
    }

    static func styled(_ text: String) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        let result = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.textColor])
        let ns = text as NSString
        // Only the header block (up to the first empty line) is highlighted.
        var headerEnd = ns.range(of: "\r\n\r\n").location
        if headerEnd == NSNotFound { headerEnd = ns.range(of: "\n\n").location }
        if headerEnd == NSNotFound { headerEnd = min(ns.length, 200_000) }
        let accent = NSColor(Palette.violet)
        let bold = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold)
        if let regex = try? NSRegularExpression(pattern: "^[A-Za-z0-9-]+:", options: .anchorsMatchLines) {
            for match in regex.matches(in: text, range: NSRange(location: 0, length: headerEnd)) {
                result.addAttributes([.foregroundColor: accent, .font: bold], range: match.range)
            }
        }
        return result
    }
}
