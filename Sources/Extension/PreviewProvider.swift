import Cocoa
import Quartz
import WebKit
import os

private let log = Logger(subsystem: "com.ertu.mdviewer.preview", category: "preview")

/// View-based Quick Look preview. The panel is only revealed after the page has
/// finished rendering, at its final size — no blank frame, no resize jump.
final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var completion: ((Error?) -> Void)?
    private var timeoutWork: DispatchWorkItem?
    private var started = Date()
    private var ownLoads = 0

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        config.suppressesIncrementalRendering = true
        webView = WKWebView(frame: NSRect(origin: .zero, size: Self.preferredSize()), configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]
        view = webView
        preferredContentSize = Self.preferredSize()
    }

    /// Fixed, screen-relative size so the panel opens at its final dimensions.
    static func preferredSize() -> NSSize {
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let width = min(980, visible.width * 0.7)
        let height = min(1100, visible.height * 0.85)
        return NSSize(width: width.rounded(), height: height.rounded())
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        finish() // never leave an earlier request unanswered if the controller is reused
        started = Date()
        let html: String
        do {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1)
                ?? String(decoding: data, as: UTF8.self)
            html = HTMLTemplate.document(markdown: text, title: url.lastPathComponent,
                                         baseDirectory: url.deletingLastPathComponent())
        } catch {
            handler(error); return
        }
        log.debug("rendered in \(Int(Date().timeIntervalSince(self.started) * 1000))ms")

        completion = handler
        // Safety net: never leave Quick Look spinning if WebKit stalls.
        let work = DispatchWorkItem { [weak self] in self?.finish() }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)

        ownLoads += 1
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func finish() {
        timeoutWork?.cancel(); timeoutWork = nil
        guard let completion else { return }
        self.completion = nil
        let ms = Int(Date().timeIntervalSince(self.started) * 1000)
        log.debug("shown after \(ms)ms")
        completion(nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish() }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url else {
            // Only the page we load ourselves may navigate; the document can't redirect itself.
            if ownLoads > 0 {
                ownLoads -= 1
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
            return
        }
        // In-page anchors scroll; web links open in the browser; nothing else is followed.
        if url.scheme == "about" {
            decisionHandler(.allow); return
        }
        decisionHandler(.cancel)
        if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
    }
}
