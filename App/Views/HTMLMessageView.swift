import AppKit
import MailmegKit
import SwiftUI
import WebKit

/// Renders an email body in a locked-down WKWebView:
/// no JavaScript, no remote loads unless allowed, links open in the browser,
/// and the view grows to fit its content so the surrounding ScrollView scrolls.
struct HTMLMessageView: NSViewRepresentable {
    let html: String?
    let plainText: String?
    let allowsRemoteContent: Bool
    @Binding var height: CGFloat
    var onMailto: (URL) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> PassthroughWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let controller = configuration.userContentController
        controller.add(context.coordinator, contentWorld: .defaultClient, name: Coordinator.heightHandler)
        controller.addUserScript(WKUserScript(
            source: Coordinator.measureScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: .defaultClient
        ))

        let webView = PassthroughWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = true
        context.coordinator.webView = webView
        context.coordinator.render(force: true)
        return webView
    }

    func updateNSView(_ webView: PassthroughWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.render(force: false)
    }

    static func dismantleNSView(_ webView: PassthroughWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.navigationDelegate = nil
    }

    // MARK: - Document

    static func document(html: String?, plainText: String?, allowsRemoteContent: Bool) -> String {
        let csp = allowsRemoteContent
            ? "default-src 'none'; img-src * data:; style-src * 'unsafe-inline'; font-src * data:; media-src * data:;"
            : "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:;"
        let body: String
        let colorScheme: String
        if let html, !html.isEmpty {
            body = html
            colorScheme = "light"
        } else {
            body = "<div class=\"mailmeg-plain\">\(HTMLText.html(fromPlainText: plainText ?? ""))</div>"
            colorScheme = "light dark"
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <meta name="color-scheme" content="\(colorScheme)">
        <style>
        html, body { margin: 0; padding: 0; }
        body { font: -apple-system-body; font-family: -apple-system, sans-serif; word-wrap: break-word; overflow-wrap: anywhere; }
        #mailmeg-root { display: flow-root; padding: 12px 16px; }
        img { max-width: 100% !important; height: auto !important; }
        table { max-width: 100% !important; }
        pre { white-space: pre-wrap; }
        .mailmeg-plain { white-space: pre-wrap; font-family: -apple-system, sans-serif; font-size: 13px; line-height: 1.45; }
        blockquote { margin-left: 0.5em; padding-left: 0.8em; border-left: 2px solid #B1CBFA; }
        .mailmeg-plain a { color: #7971EA; }
        @media (prefers-color-scheme: dark) { .mailmeg-plain a { color: #B1CBFA; } }
        </style>
        </head>
        <body><div id="mailmeg-root">\(body)</div></body>
        </html>
        """
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let heightHandler = "mailmegHeight"
        static let measureScript = """
        (function() {
          var root = document.getElementById('mailmeg-root') || document.body;
          function report() {
            var height = Math.ceil(root.getBoundingClientRect().height);
            window.webkit.messageHandlers.\(heightHandler).postMessage(height);
          }
          new ResizeObserver(report).observe(root);
          window.addEventListener('load', report);
          report();
        })();
        """

        var parent: HTMLMessageView
        weak var webView: WKWebView?
        private var renderedKey: String?

        init(_ parent: HTMLMessageView) {
            self.parent = parent
        }

        func render(force: Bool) {
            let document = HTMLMessageView.document(
                html: parent.html,
                plainText: parent.plainText,
                allowsRemoteContent: parent.allowsRemoteContent
            )
            let key = "\(parent.allowsRemoteContent)|\(document.hashValue)"
            guard force || key != renderedKey, let webView else { return }
            renderedKey = key
            let allowsRemote = parent.allowsRemoteContent
            Task { @MainActor in
                let controller = webView.configuration.userContentController
                controller.removeAllContentRuleLists()
                if !allowsRemote, let rules = await RemoteContentBlocker.ruleList() {
                    controller.add(rules)
                }
                webView.loadHTMLString(document, baseURL: nil)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.heightHandler, let value = message.body as? NSNumber else { return }
            let height = CGFloat(truncating: value)
            if height > 0, abs(height - parent.height) > 1 {
                parent.height = height
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            if url.scheme == "about" || url.scheme == "data" {
                return navigationAction.navigationType == .other ? .allow : .cancel
            }
            guard navigationAction.navigationType == .linkActivated else { return .cancel }
            switch url.scheme?.lowercased() {
            case "mailto":
                parent.onMailto(url)
            case "http", "https":
                NSWorkspace.shared.open(url)
            default:
                break
            }
            return .cancel
        }
    }
}

/// WKWebView that hands scroll events to the enclosing SwiftUI ScrollView.
final class PassthroughWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

/// Compiled WebKit content blocker that stops all remote loads (tracking pixels etc.).
@MainActor
enum RemoteContentBlocker {
    private static var cached: WKContentRuleList?

    static func ruleList() async -> WKContentRuleList? {
        if let cached { return cached }
        let rules = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#
        let list = try? await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "de.mailmeg.block-remote-content",
            encodedContentRuleList: rules
        )
        cached = list
        return list
    }
}
