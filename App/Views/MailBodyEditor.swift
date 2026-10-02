import AppKit
import MailmegKit
import SwiftUI

/// Rich-text editor for the message body. Keeps `text` (the plain-text body) and
/// `runs` (the same text with formatting, nil while nothing is formatted) in sync, and
/// can place the cursor at a given position when the window opens.
struct MailBodyEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var runs: [RichTextRun]?
    var initialCursor: Int
    var focusOnAppear: Bool
    var controller: RichTextController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFontPanel = true
        textView.drawsBackground = false
        textView.font = RichTextController.baseFont
        textView.textColor = .textColor
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.defaultParagraphStyle = RichTextController.paragraphStyle
        textView.typingAttributes = RichTextController.baseAttributes
        textView.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue, .cursor: NSCursor.pointingHand]
        if let runs, runs.map(\.text).joined() == text {
            textView.textStorage?.setAttributedString(RichTextController.attributedString(from: runs))
        } else {
            textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: RichTextController.baseAttributes))
        }
        textView.setAccessibilityIdentifier("compose.body")
        controller.textView = textView
        controller.onChange = { [weak coordinator = context.coordinator] in coordinator?.publish() }

        let cursor = min(max(initialCursor, 0), (text as NSString).length)
        DispatchQueue.main.async {
            if focusOnAppear {
                textView.window?.makeFirstResponder(textView)
            }
            textView.setSelectedRange(NSRange(location: cursor, length: 0))
            textView.scrollRangeToVisible(NSRange(location: cursor, length: 0))
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView, let storage = textView.textStorage,
              textView.string != text else { return }
        // The body changed outside the editor (e.g. the signature was swapped): replace only
        // the part that differs, so formatting elsewhere survives.
        let old = textView.string as NSString
        let new = text as NSString
        var prefix = 0
        while prefix < old.length, prefix < new.length, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < old.length - prefix, suffix < new.length - prefix,
              old.character(at: old.length - 1 - suffix) == new.character(at: new.length - 1 - suffix) { suffix += 1 }
        let oldRange = NSRange(location: prefix, length: old.length - prefix - suffix)
        let replacement = new.substring(with: NSRange(location: prefix, length: new.length - prefix - suffix))
        let selection = textView.selectedRange()
        storage.replaceCharacters(in: oldRange, with: NSAttributedString(string: replacement, attributes: RichTextController.baseAttributes))
        textView.setSelectedRange(NSRange(location: min(selection.location, storage.length), length: 0))
        context.coordinator.publish()
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MailBodyEditor

        init(_ parent: MailBodyEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            publish()
        }

        func publish() {
            guard let textView = parent.controller.textView, let storage = textView.textStorage else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
            let runs = RichTextController.runs(from: storage)
            let formatted = runs.contains(where: \.isFormatted) ? runs : nil
            if parent.runs != formatted {
                parent.runs = formatted
            }
        }

        /// Return inside a list continues it; Return on an empty list item ends the list.
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            return parent.controller.continueList()
        }
    }
}

/// Applies formatting to the editor's text view (used by the format bar and shortcuts).
@MainActor
final class RichTextController {
    static let baseSize: CGFloat = 13.5
    static var baseFont: NSFont { .systemFont(ofSize: baseSize) }
    static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        return style
    }
    static var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraphStyle]
    }

    weak var textView: NSTextView?
    var onChange: (() -> Void)?

    // MARK: Inline styles

    func toggleTrait(_ trait: NSFontTraitMask) {
        let manager = NSFontManager.shared
        let allHave = all(.font) { value in
            manager.traits(of: (value as? NSFont) ?? Self.baseFont).contains(trait)
        }
        apply(.font) { value in
            let font = (value as? NSFont) ?? Self.baseFont
            return allHave ? manager.convert(font, toNotHaveTrait: trait) : manager.convert(font, toHaveTrait: trait)
        }
    }

    func toggleUnderline() { toggleLine(.underlineStyle) }
    func toggleStrikethrough() { toggleLine(.strikethroughStyle) }

    private func toggleLine(_ key: NSAttributedString.Key) {
        let allHave = all(key) { (($0 as? Int) ?? 0) != 0 }
        apply(key) { _ in allHave ? nil : NSUnderlineStyle.single.rawValue }
    }

    func setSize(_ size: CGFloat) {
        apply(.font) { value in
            NSFontManager.shared.convert((value as? NSFont) ?? Self.baseFont, toSize: size)
        }
    }

    func setColor(_ color: NSColor?) {
        apply(.foregroundColor) { _ in color ?? NSColor.textColor }
    }

    func clearFormatting() {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        guard range.length > 0 else {
            textView.typingAttributes = Self.baseAttributes
            return
        }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        for key in [NSAttributedString.Key.underlineStyle, .strikethroughStyle, .link] {
            storage.removeAttribute(key, range: range)
        }
        storage.addAttributes(Self.baseAttributes, range: range)
        storage.endEditing()
        textView.didChangeText()
        onChange?()
    }

    func addLink() {
        guard let textView, let window = textView.window else { return }
        let range = textView.selectedRange()
        let alert = NSAlert()
        alert.messageText = tr("Link einfügen", "Add Link")
        alert.informativeText = range.length > 0
            ? tr("Der markierte Text wird verlinkt.", "The selected text will become a link.")
            : tr("Die Adresse wird an der Einfügemarke eingefügt.", "The address is inserted at the cursor.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "https://"
        if let existing = textView.textStorage?.attribute(.link, at: min(range.location, max((textView.textStorage?.length ?? 1) - 1, 0)), effectiveRange: nil) {
            field.stringValue = (existing as? URL)?.absoluteString ?? (existing as? String) ?? ""
        }
        alert.accessoryView = field
        alert.addButton(withTitle: tr("Einfügen", "Add"))
        alert.addButton(withTitle: tr("Abbrechen", "Cancel"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            var address = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { return }
            if !address.contains(":") { address = (address.contains("@") ? "mailto:" : "https://") + address }
            self?.applyLink(address, range: range)
        }
    }

    private func applyLink(_ address: String, range: NSRange) {
        guard let textView, let storage = textView.textStorage else { return }
        if range.length == 0 {
            let display = address.hasPrefix("mailto:") ? String(address.dropFirst(7)) : address
            var attributes = textView.typingAttributes
            attributes[.link] = address
            let inserted = NSAttributedString(string: display, attributes: attributes)
            guard textView.shouldChangeText(in: range, replacementString: display) else { return }
            storage.replaceCharacters(in: range, with: inserted)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: range.location + inserted.length, length: 0))
            textView.typingAttributes.removeValue(forKey: .link)
        } else {
            guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
            storage.addAttribute(.link, value: address, range: range)
            textView.didChangeText()
        }
        onChange?()
    }

    // MARK: Lists

    enum ListStyle { case bullet, numbered }

    func toggleList(_ style: ListStyle) {
        guard let textView, let storage = textView.textStorage else { return }
        let string = storage.string as NSString
        let block = string.paragraphRange(for: textView.selectedRange())
        let paragraphs = paragraphRanges(in: block, of: string)
        let alreadyList = paragraphs.allSatisfy { prefixLength(of: string.substring(with: $0), style: style) > 0 }

        let result = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: block))
        var offset = 0
        for (index, paragraph) in paragraphs.enumerated() {
            let local = NSRange(location: paragraph.location - block.location + offset, length: paragraph.length)
            let line = string.substring(with: paragraph)
            // Remove any existing list prefix first.
            let existing = max(prefixLength(of: line, style: .bullet), prefixLength(of: line, style: .numbered))
            if existing > 0 {
                result.deleteCharacters(in: NSRange(location: local.location, length: existing))
                offset -= existing
            }
            if !alreadyList {
                let prefix = style == .bullet ? RichTextHTML.bulletPrefix : "\(index + 1). "
                let attributes = result.length > local.location
                    ? result.attributes(at: local.location, effectiveRange: nil)
                    : textView.typingAttributes
                result.insert(NSAttributedString(string: prefix, attributes: attributes), at: local.location)
                offset += (prefix as NSString).length
            }
        }
        guard textView.shouldChangeText(in: block, replacementString: result.string) else { return }
        storage.replaceCharacters(in: block, with: result)
        textView.didChangeText()
        let end = block.location + result.length
        let lastIsNewline = result.string.hasSuffix("\n")
        textView.setSelectedRange(NSRange(location: lastIsNewline ? end - 1 : end, length: 0))
        onChange?()
    }

    /// Called on Return: continues "• " and "1. " lists. Returns true if handled.
    func continueList() -> Bool {
        guard let textView, let storage = textView.textStorage else { return false }
        let selection = textView.selectedRange()
        let string = storage.string as NSString
        let paragraph = string.paragraphRange(for: NSRange(location: selection.location, length: 0))
        let line = string.substring(with: paragraph).trimmingCharacters(in: .newlines)
        let bullet = prefixLength(of: line, style: .bullet)
        let numbered = prefixLength(of: line, style: .numbered)
        guard bullet > 0 || numbered > 0 else { return false }

        if (line as NSString).length == max(bullet, numbered) {
            // Empty item: end the list.
            let prefixRange = NSRange(location: paragraph.location, length: max(bullet, numbered))
            guard textView.shouldChangeText(in: prefixRange, replacementString: "") else { return true }
            storage.replaceCharacters(in: prefixRange, with: "")
            textView.didChangeText()
            onChange?()
            return true
        }
        var prefix = RichTextHTML.bulletPrefix
        if numbered > 0, let number = Int(line.prefix { $0.isNumber }) {
            prefix = "\(number + 1). "
        }
        textView.insertText("\n" + prefix, replacementRange: selection)
        return true
    }

    private func prefixLength(of line: String, style: ListStyle) -> Int {
        switch style {
        case .bullet: return line.hasPrefix(RichTextHTML.bulletPrefix) ? (RichTextHTML.bulletPrefix as NSString).length : 0
        case .numbered: return RichTextHTML.numberedPrefixLength(line) ?? 0
        }
    }

    private func paragraphRanges(in block: NSRange, of string: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var location = block.location
        let end = block.location + block.length
        repeat {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            var content = paragraph
            let text = string.substring(with: paragraph)
            if text.hasSuffix("\n") { content.length -= 1 }
            ranges.append(content)
            location = paragraph.location + paragraph.length
        } while location < end
        return ranges
    }

    // MARK: Helpers

    private func all(_ key: NSAttributedString.Key, _ test: (Any?) -> Bool) -> Bool {
        guard let textView, let storage = textView.textStorage else { return false }
        let range = textView.selectedRange()
        if range.length == 0 { return test(textView.typingAttributes[key]) }
        var result = true
        storage.enumerateAttribute(key, in: range) { value, _, stop in
            if !test(value) {
                result = false
                stop.pointee = true
            }
        }
        return result
    }

    /// Applies a transform to the selection, or to the typing attributes if nothing is selected.
    private func apply(_ key: NSAttributedString.Key, _ transform: (Any?) -> Any?) {
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        if range.length == 0 {
            textView.typingAttributes[key] = transform(textView.typingAttributes[key])
            return
        }
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        storage.beginEditing()
        storage.enumerateAttribute(key, in: range) { value, subrange, _ in
            if let newValue = transform(value) {
                storage.addAttribute(key, value: newValue, range: subrange)
            } else {
                storage.removeAttribute(key, range: subrange)
            }
        }
        storage.endEditing()
        textView.didChangeText()
        onChange?()
    }

    // MARK: Conversion

    static func runs(from string: NSAttributedString) -> [RichTextRun] {
        var runs: [RichTextRun] = []
        let manager = NSFontManager.shared
        string.enumerateAttributes(in: NSRange(location: 0, length: string.length)) { attributes, range, _ in
            let font = (attributes[.font] as? NSFont) ?? baseFont
            let traits = manager.traits(of: font)
            var run = RichTextRun(text: (string.string as NSString).substring(with: range))
            run.isBold = traits.contains(.boldFontMask)
            run.isItalic = traits.contains(.italicFontMask)
            run.isUnderlined = ((attributes[.underlineStyle] as? Int) ?? 0) != 0
            run.isStruck = ((attributes[.strikethroughStyle] as? Int) ?? 0) != 0
            if let link = attributes[.link] {
                run.link = (link as? URL)?.absoluteString ?? (link as? String)
            }
            if let color = attributes[.foregroundColor] as? NSColor, !isDefault(color) {
                run.colorHex = hex(color)
            }
            if abs(font.pointSize - baseSize) > 0.5 {
                run.fontSize = Double(font.pointSize)
            }
            if let last = runs.last, last.with(text: "") == run.with(text: "") {
                runs[runs.count - 1].text += run.text
            } else {
                runs.append(run)
            }
        }
        return runs
    }

    static func attributedString(from runs: [RichTextRun]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let manager = NSFontManager.shared
        for run in runs {
            var attributes = baseAttributes
            var font = baseFont
            if let size = run.fontSize { font = manager.convert(font, toSize: CGFloat(size)) }
            if run.isBold { font = manager.convert(font, toHaveTrait: .boldFontMask) }
            if run.isItalic { font = manager.convert(font, toHaveTrait: .italicFontMask) }
            attributes[.font] = font
            if run.isUnderlined { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if run.isStruck { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let link = run.link { attributes[.link] = link }
            if let hex = run.colorHex { attributes[.foregroundColor] = NSColor(Color(hex: hex)) }
            result.append(NSAttributedString(string: run.text, attributes: attributes))
        }
        return result
    }

    private static func isDefault(_ color: NSColor) -> Bool {
        if color == .textColor || color == .labelColor || color == .controlTextColor { return true }
        return color.type == .catalog && (color.colorNameComponent == "textColor" || color.colorNameComponent == "labelColor")
    }

    static func hex(_ color: NSColor) -> String? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let r = Int((rgb.redComponent * 255).rounded()), g = Int((rgb.greenComponent * 255).rounded()), b = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

/// Formatting controls above the message body.
struct FormatBar: View {
    let controller: RichTextController

    private struct TextColor: Identifiable {
        let name: String
        let hex: String?
        var id: String { name }
    }

    private let colors: [TextColor] = [
        TextColor(name: tr("Standard", "Default"), hex: nil),
        TextColor(name: tr("Violett", "Violet"), hex: "#7971ea"),
        TextColor(name: tr("Blau", "Blue"), hex: "#1a73e8"),
        TextColor(name: tr("Grün", "Green"), hex: "#188038"),
        TextColor(name: tr("Orange", "Orange"), hex: "#e8710a"),
        TextColor(name: tr("Rot", "Red"), hex: "#d93025"),
        TextColor(name: tr("Grau", "Gray"), hex: "#5f6368"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            formatButton("bold", tr("Fett (⌘B)", "Bold (⌘B)"), id: "format.bold") { controller.toggleTrait(.boldFontMask) }
                .keyboardShortcut("b")
            formatButton("italic", tr("Kursiv (⌘I)", "Italic (⌘I)"), id: "format.italic") { controller.toggleTrait(.italicFontMask) }
                .keyboardShortcut("i")
            formatButton("underline", tr("Unterstrichen (⌘U)", "Underline (⌘U)"), id: "format.underline") { controller.toggleUnderline() }
                .keyboardShortcut("u")
            formatButton("strikethrough", tr("Durchgestrichen", "Strikethrough"), id: "format.strikethrough") { controller.toggleStrikethrough() }
            separator
            formatButton("list.bullet", tr("Aufzählung", "Bulleted List"), id: "format.bullets") { controller.toggleList(.bullet) }
                .keyboardShortcut("7", modifiers: [.command, .shift])
            formatButton("list.number", tr("Nummerierte Liste", "Numbered List"), id: "format.numbers") { controller.toggleList(.numbered) }
                .keyboardShortcut("8", modifiers: [.command, .shift])
            separator
            formatButton("link", tr("Link einfügen (⌘K)", "Add Link (⌘K)"), id: "format.link") { controller.addLink() }
                .keyboardShortcut("k")
            Menu {
                Button(tr("Klein", "Small")) { controller.setSize(11) }
                Button(tr("Normal", "Normal")) { controller.setSize(RichTextController.baseSize) }
                Button(tr("Groß", "Large")) { controller.setSize(17) }
                Button(tr("Sehr groß", "Huge")) { controller.setSize(22) }
            } label: {
                formatLabel("textformat.size")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(tr("Schriftgröße", "Text Size"))
            Menu {
                ForEach(colors) { color in
                    Button {
                        controller.setColor(color.hex.map { NSColor(Color(hex: $0)) })
                    } label: {
                        Label {
                            Text(color.name)
                        } icon: {
                            Image(nsImage: swatch(color.hex))
                        }
                    }
                }
            } label: {
                formatLabel("paintpalette")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(tr("Textfarbe", "Text Color"))
            separator
            formatButton("eraser", tr("Formatierung entfernen", "Clear Formatting"), id: "format.clear") { controller.clearFormatting() }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private var separator: some View {
        Divider().frame(height: 16).padding(.horizontal, 4)
    }

    private func formatLabel(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 24)
            .contentShape(Rectangle())
    }

    private func formatButton(_ systemImage: String, _ help: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { formatLabel(systemImage) }
            .buttonStyle(.borderless)
            .help(help)
            .accessibilityLabel(help)
            .accessibilityIdentifier(id)
    }

    private func swatch(_ hex: String?) -> NSImage {
        let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let color = hex.map { NSColor(Color(hex: $0)) } ?? NSColor.textColor
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
