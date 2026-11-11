import Cocoa
import WebKit

/// Read-only Markdown document with live reload when the file changes on disk.
final class MarkdownDocument: NSDocument {
    private(set) var markdown = ""
    weak var viewController: MarkdownViewController?
    private var watcher: DispatchSourceFileSystemObject?

    override class var autosavesInPlace: Bool { false }
    override var isDocumentEdited: Bool { false }

    override func read(from data: Data, ofType typeName: String) throws {
        markdown = Self.decode(data)
    }

    override func data(ofType typeName: String) throws -> Data { Data(markdown.utf8) }

    static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? String(decoding: data, as: UTF8.self)
    }

    override func makeWindowControllers() {
        let vc = MarkdownViewController(document: self)
        viewController = vc
        let window = NSWindow(contentViewController: vc)
        window.setContentSize(NSSize(width: 960, height: 1000))
        window.minSize = NSSize(width: 400, height: 300)
        window.tabbingMode = .preferred
        let wc = NSWindowController(window: window)
        wc.shouldCascadeWindows = true
        addWindowController(wc)
        if NSApp.windows.filter({ $0.isVisible }).isEmpty { window.center() }
        startWatching()
    }

    override func close() {
        watcher?.cancel(); watcher = nil
        super.close()
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let webView = viewController?.webView else { throw CocoaError(.featureUnsupported) }
        let info = printInfo.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        let op = webView.printOperation(with: info)
        op.view?.frame = webView.bounds
        return op
    }

    // MARK: - Live reload

    func reloadFromDisk() {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return }
        let text = Self.decode(data)
        guard text != markdown else { return }
        markdown = text
        viewController?.render(preserveScroll: true)
    }

    private func startWatching() {
        watcher?.cancel(); watcher = nil
        guard let path = fileURL?.path else { return }
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename, .attrib], queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            let ev = src.data
            if ev.contains(.delete) || ev.contains(.rename) {
                // Atomic save (write temp + rename): re-attach to the new file.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.startWatching()
                    self.reloadFromDisk()
                }
            } else {
                self.reloadFromDisk()
            }
        }
        src.setCancelHandler { Darwin.close(fd) }
        src.resume()
        watcher = src
    }
}

final class MarkdownViewController: NSViewController, WKNavigationDelegate {
    let webView: WKWebView
    private weak var document: MarkdownDocument?
    private var pendingScroll: Double?
    private var hasLoaded = false
    private var ownLoads = 0

    init(document: MarkdownDocument) {
        self.document = document
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 1000), configuration: config)
        super.init(nibName: nil, bundle: nil)
        webView.navigationDelegate = self
        webView.allowsMagnification = true
        webView.setValue(false, forKey: "drawsBackground")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() { view = webView }

    override func viewDidLoad() {
        super.viewDidLoad()
        render(preserveScroll: false)
    }

    func render(preserveScroll: Bool) {
        guard let doc = document else { return }
        let base = doc.fileURL?.deletingLastPathComponent()
        let html = HTMLTemplate.document(markdown: doc.markdown, title: doc.displayName, baseDirectory: base)
        if preserveScroll && hasLoaded {
            webView.evaluateJavaScript("window.scrollY") { [weak self] value, _ in
                guard let self else { return }
                self.pendingScroll = (value as? NSNumber)?.doubleValue
                self.ownLoads += 1
                self.webView.loadHTMLString(html, baseURL: base)
            }
        } else {
            ownLoads += 1
            webView.loadHTMLString(html, baseURL: base)
        }
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hasLoaded = true
        if let y = pendingScroll {
            pendingScroll = nil
            webView.evaluateJavaScript("window.scrollTo(0, \(y))", completionHandler: nil)
        }
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
        decisionHandler(.cancel)

        // In-page anchor (#heading)
        let strip: (URL?) -> String? = { $0?.absoluteString.components(separatedBy: "#").first }
        if let fragment = url.fragment, strip(url) == strip(webView.url) {
            let id = fragment.removingPercentEncoding ?? fragment
            let json = (try? String(data: JSONEncoder().encode(id), encoding: .utf8)) ?? "\"\""
            webView.evaluateJavaScript(
                "var e=document.getElementById(\(json))||document.getElementById(\(json).toLowerCase());if(e)e.scrollIntoView({behavior:'smooth'});",
                completionHandler: nil)
            return
        }

        if url.isFileURL {
            let ext = url.pathExtension.lowercased()
            if ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdx"].contains(ext) {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            } else {
                // Never launch a local file from a link; show it in Finder instead.
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            return
        }
        if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Actions

    @objc func reloadFromDisk(_ sender: Any?) {
        guard let doc = document else { return }
        doc.reloadFromDisk()
        render(preserveScroll: true)
    }

    @objc func showInFinder(_ sender: Any?) {
        if let url = document?.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    @objc func openInEditor(_ sender: Any?) {
        guard let url = document?.fileURL else { return }
        // Prefer the system text editor for the file (e.g. TextEdit / VS Code if set as editor).
        if let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText) {
            NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    @objc func zoomIn(_ sender: Any?) { webView.pageZoom = min(webView.pageZoom + 0.1, 3) }
    @objc func zoomOut(_ sender: Any?) { webView.pageZoom = max(webView.pageZoom - 0.1, 0.5) }
    @objc func actualSize(_ sender: Any?) { webView.pageZoom = 1 }
}
