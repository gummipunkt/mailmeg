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
    /// Quoted earlier messages start folded away.
    var collapsesQuotes = true
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
        controller.addUserScript(WKUserScript(
            source: Coordinator.quoteScript,
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

    static func document(html: String?, plainText: String?, allowsRemoteContent: Bool, collapsesQuotes: Bool = true) -> String {
        let showLabel = HTMLText.escape(tr("Zitat anzeigen", "Show quoted text"))
        let hideLabel = HTMLText.escape(tr("Zitat ausblenden", "Hide quoted text"))
        let csp = allowsRemoteContent
            ? "default-src 'none'; img-src * data:; style-src * 'unsafe-inline'; font-src * data:; media-src * data:;"
            : "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:;"
        let body: String
        let colorScheme: String
        if let html, !html.isEmpty {
            body = html
            colorScheme = "light"
        } else {
            // Plain text: the quote at the end goes into a native disclosure element.
            let parts = QuotedText.split(plainText ?? "")
            var plain = "<div class=\"mailmeg-plain\">\(HTMLText.html(fromPlainText: parts.body))</div>"
            if let quote = parts.quote {
                plain += "<details class=\"mailmeg-quote\"\(collapsesQuotes ? "" : " open")>"
                    + "<summary data-show=\"\(showLabel)\" data-hide=\"\(hideLabel)\"></summary>"
                    + "<div class=\"mailmeg-plain mailmeg-quoted\">\(HTMLText.html(fromPlainText: quote))</div></details>"
            }
            body = plain
            colorScheme = "light dark"
        }
        return """
        <!DOCTYPE html>
        <html class="\(html?.isEmpty == false ? "rich" : "plain")" data-quotes="\(collapsesQuotes ? "collapsed" : "expanded")" data-show="\(showLabel)" data-hide="\(hideLabel)">
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
        details.mailmeg-quote { margin: 10px 0 2px; }
        details.mailmeg-quote > summary { list-style: none; display: inline-flex; align-items: center; gap: 6px; cursor: pointer;
          -webkit-user-select: none; font: 600 11px -apple-system, sans-serif; color: #6A63D8; background: #ECEEFE;
          border-radius: 999px; padding: 3px 10px 3px 9px; outline: none; }
        details.mailmeg-quote > summary::-webkit-details-marker { display: none; }
        details.mailmeg-quote > summary::before { content: "•••"; letter-spacing: 1px; font-size: 10px; }
        details.mailmeg-quote > summary::after { content: attr(data-show); }
        details.mailmeg-quote[open] > summary::after { content: attr(data-hide); }
        details.mailmeg-quote > summary:hover { background: #DFE2FE; }
        details.mailmeg-quote[open] > summary { margin-bottom: 10px; }
        .mailmeg-quoted { color: #6B6E8C; border-left: 2px solid #B1CBFA; padding-left: 10px; }
        html.plain, html.plain body { background: #FAF7FF; }
        @media (prefers-color-scheme: dark) {
          html.plain, html.plain body { background: #272445; color: #E9E7FB; }
          .mailmeg-plain a { color: #B1CBFA; }
          html.plain details.mailmeg-quote > summary { color: #C9CCFF; background: #34365C; }
          html.plain details.mailmeg-quote > summary:hover { background: #3F4170; }
          html.plain .mailmeg-quoted { color: #A3A6C9; border-left-color: #4A4D80; }
        }
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

        /// Finds the quoted earlier messages at the end of an HTML mail and moves them into a
        /// disclosure element. Mail HTML itself runs no scripts; this runs in the app's own world.
        static let quoteScript = #"""
        (function() {
          var html = document.documentElement;
          var root = document.getElementById('mailmeg-root');
          if (!root || !html.classList.contains('rich')) return;
          var containers = '.gmail_quote, .gmail_extra, .yahoo_quoted, .protonmail_quote, .zmail_extra, .tutanota_quote, blockquote';
          var separators = '#divRplyFwdMsg, #appendonsend, .OutlookMessageHeader, ' +
            'div[style*="border-top:solid #E1E1E1"], div[style*="border-top: solid #E1E1E1"], ' +
            'div[style*="border-top:solid #B5C4DF"], div[style*="border-top: solid #B5C4DF"]';
          var forwarded = /^[-\s]*(forwarded message|weitergeleitete nachricht|begin forwarded message|anfang der weitergeleiteten)/i;
          var attribution = /(wrote|schrieb|geschrieben|écrit|escribió|ha scritto)\s*:\s*$/i;

          function clean(text) { return text.replace(/\s+/g, ' ').trim(); }
          function textBefore(node, within) {
            var range = document.createRange();
            range.setStart(within, 0);
            range.setEndBefore(node);
            return clean(range.toString());
          }
          function textAfter(node) {
            var range = document.createRange();
            range.setStartAfter(node);
            range.setEnd(root, root.childNodes.length);
            return clean(range.toString());
          }
          function isBlank(node) {
            if (node.nodeType === 3) return !clean(node.nodeValue);
            return node.nodeType === 1 && node.tagName === 'BR';
          }

          var found = null;
          var candidates = root.querySelectorAll(containers + ', ' + separators);
          for (var i = 0; i < candidates.length && !found; i++) {
            var el = candidates[i];
            if (!textBefore(el, root)) continue;
            if (forwarded.test(clean(el.textContent))) continue;
            if (el.matches(separators)) {
              // Outlook: a header block, the old message follows it as siblings.
              var start = el;
              while (start.parentNode !== root && !textBefore(start, start.parentNode)) start = start.parentNode;
              var rule = start.previousElementSibling;
              if (rule && rule.tagName === 'HR') start = rule;
              var nodes = [];
              for (var n = start; n; n = n.nextSibling) nodes.push(n);
              for (var p = start.parentNode; p && p !== root; p = p.parentNode) {
                for (var s = p.nextSibling; s; s = s.nextSibling) nodes.push(s);
              }
              found = nodes;
            } else {
              // A quote block: only when nothing is written below it.
              if (textAfter(el)) continue;
              var nodes = [el];
              var blanks = [];
              for (var b = el.previousSibling; b; b = b.previousSibling) {
                if (isBlank(b)) { blanks.push(b); continue; }
                var label = clean(b.textContent || '');
                if (label.length < 300 && attribution.test(label)) {
                  nodes = [b].concat(blanks.reverse(), nodes);
                }
                break;
              }
              found = nodes;
            }
          }
          if (!found || !found.length) return;

          var details = document.createElement('details');
          details.className = 'mailmeg-quote';
          if (html.dataset.quotes === 'expanded') details.open = true;
          var summary = document.createElement('summary');
          summary.setAttribute('data-show', html.dataset.show || '');
          summary.setAttribute('data-hide', html.dataset.hide || '');
          details.appendChild(summary);
          var box = document.createElement('div');
          details.appendChild(box);
          found[0].parentNode.insertBefore(details, found[0]);
          found.forEach(function(node) { box.appendChild(node); });
        })();
        """#

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
                allowsRemoteContent: parent.allowsRemoteContent,
                collapsesQuotes: parent.collapsesQuotes
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
