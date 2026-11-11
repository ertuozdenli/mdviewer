// Generates the README's before/after demo:
//   demo-before.gif  a Markdown file in Finder → Space → macOS's plain-text preview
//   demo-after.gif   the same file → Space → MD Viewer's rendered preview
// The desktop, Finder window and panel frame are an illustration drawn in HTML. The
// document in the "after" panel is rendered with the same renderer and stylesheet the
// Quick Look extension uses. Both GIFs share frame timing so they loop in step.
// Run via ./Scripts/make-demo-gif.sh
import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: demo-gif <input.md> <output-directory>")
    exit(1)
}
let mdURL = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
let markdown = try! String(contentsOf: mdURL, encoding: .utf8)
let fileName = mdURL.lastPathComponent

let canvas = NSSize(width: 620, height: 540)
let scale: CGFloat = 1.5

enum Variant {
    case before, after

    var outputName: String { self == .before ? "demo-before.gif" : "demo-after.gif" }
    var openWith: String { self == .before ? "Open with TextEdit" : "Open with MD Viewer" }
}

func scene(_ variant: Variant) -> String {
    let rows: [(icon: String, name: String, size: String, kind: String)] = [
        ("folder", "Invoices", "--", "Folder"),
        ("file", "meeting-notes.txt", "2 KB", "Plain Text"),
        ("file md", fileName, "1 KB", "Markdown"),
        ("file", "budget.pdf", "184 KB", "PDF Document"),
        ("file", "team-photo.jpg", "2.1 MB", "JPEG Image"),
    ]
    let rowHTML = rows.map { r in
        """
        <div class="row\(r.name == fileName ? " selected" : "")">
          <span class="name"><i class="\(r.icon)"></i>\(r.name)</span>
          <span class="size">\(r.size)</span><span class="kind">\(r.kind)</span>
        </div>
        """
    }.joined()
    let sidebar = ["Recents", "Applications", "Desktop", "Documents", "Downloads"].map {
        "<div class=\"side\($0 == "Documents" ? " active" : "")\"><i></i>\($0)</div>"
    }.joined()

    let document: String
    switch variant {
    case .before:
        document = "<div class=\"doc raw\" id=\"doc\"><pre>\(MarkdownRenderer.escape(markdown))</pre></div>"
    case .after:
        // The extension's own renderer and stylesheet.
        document = "<div class=\"doc\" id=\"doc\"><article class=\"markdown-body\">"
            + MarkdownRenderer().render(markdown) + "</article></div>"
    }

    return """
    <!DOCTYPE html><html><head><meta charset="utf-8">
    <style>\(HTMLTemplate.css)</style>
    <style>
    html, body { width: \(Int(canvas.width))px; height: \(Int(canvas.height))px; overflow: hidden; }
    .desk {
      position: absolute; inset: 0; overflow: hidden;
      font: 13px/1.3 -apple-system, "SF Pro Text", sans-serif; color: #e4e4e6;
      background: linear-gradient(135deg, #16245c 0%, #4a3a9c 42%, #c2587c 78%, #ee9a5f 100%);
    }
    .menubar {
      position: absolute; inset: 0 0 auto 0; height: 26px; padding: 0 16px; display: flex; gap: 18px;
      align-items: center; background: rgba(18, 18, 30, .38); color: #fff;
    }
    .menubar b { font-weight: 700; }

    .finder {
      position: absolute; left: 30px; top: 52px; width: 560px; height: 430px; display: flex;
      background: #1e1e20; border-radius: 12px; overflow: hidden;
      box-shadow: 0 0 0 1px rgba(255,255,255,.12), 0 24px 60px rgba(0,0,0,.5);
    }
    .sidebar { width: 148px; background: #2a2a2d; padding: 14px 10px; }
    .lights { display: flex; gap: 8px; margin: 2px 0 22px 4px; }
    .lights i { width: 12px; height: 12px; border-radius: 50%; }
    .lights i:nth-child(1) { background: #ff5f57; } .lights i:nth-child(2) { background: #febc2e; }
    .lights i:nth-child(3) { background: #28c840; }
    .sidebar .group { margin: 0 0 6px 6px; font-size: 11px; font-weight: 600; color: #8e8e93; }
    .side { display: flex; align-items: center; gap: 8px; padding: 5px 6px; border-radius: 6px; }
    .side i { width: 14px; height: 12px; border-radius: 3px; background: #3b9cf5; }
    .side.active { background: #3d3d41; }
    .main { flex: 1; display: flex; flex-direction: column; }
    .toolbar { height: 50px; display: flex; align-items: center; gap: 14px; padding: 0 16px; border-bottom: 1px solid #000; }
    .toolbar .nav { color: #8e8e93; font-size: 20px; letter-spacing: 10px; }
    .toolbar .title { font-weight: 700; font-size: 15px; }
    .head, .row { display: flex; align-items: center; padding: 0 16px; }
    .head { height: 26px; color: #9a9aa0; font-size: 12px; border-bottom: 1px solid #333336; }
    .row { height: 30px; margin: 0 8px; padding: 0 8px; border-radius: 6px; }
    .row:nth-child(even) { background: #252528; }
    .row.selected { background: #0b5fd9; color: #fff; }
    .name { flex: 1; display: flex; align-items: center; gap: 9px; }
    .size { width: 62px; text-align: right; padding-right: 16px; } .kind { width: 108px; }
    .row:not(.selected) .size, .row:not(.selected) .kind { color: #9a9aa0; }
    i.folder { width: 18px; height: 14px; border-radius: 3px; background: #3b9cf5; }
    i.file { width: 14px; height: 18px; border-radius: 2px; background: #dcdce0; }
    i.file.md { background: linear-gradient(#fff 0 30%, #b8c4d6 30% 100%); }

    .keycap {
      position: absolute; left: 50%; bottom: 26px; width: 220px; height: 52px; margin-left: -110px; display: none;
      align-items: center; justify-content: center; border-radius: 12px; background: #f2f3f5; color: #1f2328;
      font-size: 17px; font-weight: 500; box-shadow: 0 5px 0 #6b6f76, 0 14px 30px rgba(0,0,0,.45);
    }
    .s-key .keycap { display: flex; }

    .ql {
      position: absolute; left: 40px; top: 38px; width: 540px; height: 474px; opacity: 0;
      background: \(variant == .before ? "#1e1e1e" : "#0d1117"); border-radius: 12px; overflow: hidden;
      box-shadow: 0 0 0 1px rgba(255,255,255,.14), 0 30px 80px rgba(0,0,0,.65);
    }
    .s-ql1 .ql { opacity: .55; transform: scale(.94); }
    .s-ql2 .ql { opacity: 1; }
    .qlbar { height: 38px; display: flex; align-items: center; gap: 10px; padding: 0 12px; background: #252528; }
    .qlbar .x {
      width: 14px; height: 14px; border-radius: 50%; background: #8e8e93; color: #252528;
      font-size: 11px; font-weight: 700; line-height: 14px; text-align: center;
    }
    .qlbar .fname { flex: 1; font-weight: 600; }
    .qlbar .open { padding: 3px 10px; border-radius: 6px; background: #3d3d41; font-size: 12px; }
    .doc { height: 436px; overflow: hidden; font: 16px/1.6 -apple-system, "SF Pro Text", sans-serif; color: var(--fg); }
    .doc .markdown-body { padding: 26px 32px 40px; }
    .doc.raw pre {
      margin: 0; padding: 18px 22px 30px; border-radius: 0; background: transparent; overflow: visible;
      white-space: pre-wrap; color: #d6d6da; font: 12.5px/1.6 ui-monospace, "SF Mono", Menlo, monospace;
    }
    </style></head><body><div class="desk">
      <div class="menubar"><b>Finder</b><span>File</span><span>Edit</span><span>View</span><span>Go</span><span>Window</span><span>Help</span></div>
      <div class="finder">
        <div class="sidebar"><div class="lights"><i></i><i></i><i></i></div><div class="group">Favourites</div>\(sidebar)</div>
        <div class="main">
          <div class="toolbar"><span class="nav">‹›</span><span class="title">Documents</span></div>
          <div class="head"><span class="name">Name</span><span class="size">Size</span><span class="kind">Kind</span></div>
          <div class="rows">\(rowHTML)</div>
        </div>
      </div>
      <div class="keycap">space</div>
      <div class="ql">
        <div class="qlbar"><span class="x">×</span><span class="fname">\(fileName)</span><span class="open">\(variant.openWith)</span></div>
        \(document)
      </div>
    </div></body></html>
    """
}

@MainActor
final class Driver: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let window: NSWindow
    private var loadContinuation: CheckedContinuation<Void, Never>?
    var frames: [(CGImage, Double)] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: NSRect(origin: .zero, size: canvas), configuration: config)
        window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: canvas.width, height: canvas.height),
                          styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = webView
        webView.navigationDelegate = self
    }

    func load(_ html: String) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            loadContinuation = c
            webView.loadHTMLString(html, baseURL: nil)
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    @discardableResult
    func js(_ script: String) async -> Any? {
        await withCheckedContinuation { (c: CheckedContinuation<Any?, Never>) in
            webView.evaluateJavaScript(script) { value, _ in c.resume(returning: value) }
        }
    }

    /// Snapshots the scene and scales it to the GIF's pixel size.
    func capture(delay: Double) async {
        try? await Task.sleep(nanoseconds: 80_000_000)
        let config = WKSnapshotConfiguration()
        config.rect = NSRect(origin: .zero, size: canvas)
        let image: NSImage = await withCheckedContinuation { c in
            webView.takeSnapshot(with: config) { image, error in
                guard let image else { fatalError("snapshot failed: \(String(describing: error))") }
                c.resume(returning: image)
            }
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * scale),
                                   pixelsHigh: Int(canvas.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = canvas
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: canvas))
        NSGraphicsContext.restoreGraphicsState()
        frames.append((rep.cgImage!, delay))
    }

    func state(_ name: String) async {
        await js("document.querySelector('.desk').className = 'desk \(name)'")
    }

    /// Records one variant. Frame count and delays are identical for both variants.
    func record(_ variant: Variant) async {
        frames = []
        await load(scene(variant))

        await state("")
        await capture(delay: 1.5) // file selected in Finder
        await state("s-key")
        await capture(delay: 0.7) // press Space
        await state("s-ql1")
        await capture(delay: 0.05)
        await state("s-ql2")
        await capture(delay: 1.9) // preview open

        let doc = "document.getElementById('doc')"
        let maxScroll = (await js("\(doc).scrollHeight - \(doc).clientHeight") as? NSNumber)?.doubleValue ?? 0
        let steps = 14
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            await js("\(doc).scrollTop = \(maxScroll * t * t * (3 - 2 * t))")
            await capture(delay: i == steps ? 2.4 : 0.06)
        }
        writeGIF(to: outDir.appendingPathComponent(variant.outputName))
    }

    func writeGIF(to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { fatalError("cannot create GIF") }
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        for (image, delay) in frames {
            CGImageDestinationAddImage(dest, image, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay,
                ],
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { fatalError("cannot write GIF") }
        print("wrote \(url.path) (\(frames.count) frames)")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    let driver = Driver()
    await driver.record(.before)
    await driver.record(.after)
    exit(0)
}
app.run()
