import AppKit
import SwiftUI

/// Plain-text editor for the message body that can place the cursor at a given
/// position when the window opens (e.g. above or below the quoted message).
struct MailBodyEditor: NSViewRepresentable {
    @Binding var text: String
    var initialCursor: Int
    var focusOnAppear: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13.5)
        textView.textContainerInset = NSSize(width: 10, height: 12)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph
        textView.string = text
        textView.setAccessibilityIdentifier("compose.body")

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
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        let selection = textView.selectedRange()
        textView.string = text
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MailBodyEditor

        init(_ parent: MailBodyEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
