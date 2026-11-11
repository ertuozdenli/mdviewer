// Generates docs/demo.gif: raw Markdown → press Space → rendered preview.
// Frames are rendered off-screen with the same renderer and stylesheet the
// Quick Look extension uses. Run via ./Scripts/make-demo-gif.sh
import AppKit
import ImageIO
import UniformTypeIdentifiers
import WebKit

let args = CommandLine.arguments
guard args.count == 3 else {
    print("usage: demo-gif <input.md> <output.gif>")
    exit(1)
}
let mdURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let markdown = try! String(contentsOf: mdURL, encoding: .utf8)

let contentSize = NSSize(width: 760, height: 560)
let barHeight: CGFloat = 40
let scale: CGFloat = 1.5

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
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
        webView = WKWebView(frame: NSRect(origin: .zero, size: contentSize), configuration: config)
        window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: contentSize.width, height: contentSize.height),
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
        try? await Task.sleep(nanoseconds: 250_000_000)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func js(_ script: String) async -> Any? {
        await withCheckedContinuation { (c: CheckedContinuation<Any?, Never>) in
            webView.evaluateJavaScript(script) { value, _ in c.resume(returning: value) }
        }
    }

    func snapshot() async -> NSImage {
        let config = WKSnapshotConfiguration()
        config.rect = NSRect(origin: .zero, size: contentSize)
        return await withCheckedContinuation { (c: CheckedContinuation<NSImage, Never>) in
            webView.takeSnapshot(with: config) { image, error in
                guard let image else { fatalError("snapshot failed: \(String(describing: error))") }
                c.resume(returning: image)
            }
        }
    }

    /// Draws one GIF frame: a title bar (file name + state label) above the page snapshot.
    func compose(_ page: NSImage, label: String, accent: NSColor, keycap: Bool) -> CGImage {
        let total = NSSize(width: contentSize.width, height: contentSize.height + barHeight)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(total.width * scale),
                                   pixelsHigh: Int(total.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = total
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high

        color(0x0d1117).setFill()
        NSRect(origin: .zero, size: total).fill()
        page.draw(in: NSRect(origin: .zero, size: contentSize))

        // Title bar
        let bar = NSRect(x: 0, y: contentSize.height, width: total.width, height: barHeight)
        color(0x22262d).setFill()
        bar.fill()
        color(0x3d444d).setFill()
        NSRect(x: 0, y: contentSize.height, width: total.width, height: 1).fill()

        let name = NSAttributedString(string: mdURL.lastPathComponent, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: color(0xe6edf3),
        ])
        name.draw(at: NSPoint(x: 16, y: bar.midY - name.size().height / 2))

        let text = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: accent,
        ])
        let ts = text.size()
        let pill = NSRect(x: total.width - ts.width - 36, y: bar.midY - 12, width: ts.width + 20, height: 24)
        accent.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 12, yRadius: 12).fill()
        text.draw(at: NSPoint(x: pill.minX + 10, y: pill.midY - ts.height / 2))

        if keycap {
            color(0x000000).withAlphaComponent(0.35).setFill()
            NSRect(origin: .zero, size: contentSize).fill(using: .sourceOver)
            let key = NSRect(x: total.width / 2 - 120, y: 56, width: 240, height: 56)
            color(0x30363d).setFill()
            NSBezierPath(roundedRect: key.offsetBy(dx: 0, dy: -4), xRadius: 12, yRadius: 12).fill()
            color(0xf0f3f6).setFill()
            NSBezierPath(roundedRect: key, xRadius: 12, yRadius: 12).fill()
            let k = NSAttributedString(string: "space", attributes: [
                .font: NSFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: color(0x1f2328),
            ])
            k.draw(at: NSPoint(x: key.midX - k.size().width / 2, y: key.midY - k.size().height / 2))
        }

        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }

    func run() async {
        let gray = color(0x9198a1)
        let green = color(0x3fb950)

        // 1. The file as macOS shows it without the extension: plain text.
        let rawPage = """
        <!DOCTYPE html><html><head><meta charset="utf-8"><style>
        html, body { margin: 0; background: #0d1117; }
        pre { margin: 0; padding: 22px 28px; color: #c9d1d9; white-space: pre-wrap;
              font: 13px/1.55 ui-monospace, "SF Mono", Menlo, monospace; }
        </style></head><body><pre>\(MarkdownRenderer.escape(markdown))</pre></body></html>
        """
        await load(rawPage)
        let raw = await snapshot()
        frames.append((compose(raw, label: "Plain text", accent: gray, keycap: false), 1.8))
        frames.append((compose(raw, label: "Plain text", accent: gray, keycap: true), 0.7))

        // 2. The same file through MD Viewer's renderer.
        let html = HTMLTemplate.page(title: mdURL.lastPathComponent, body: MarkdownRenderer().render(markdown))
        await load(html)
        let label = "MD Viewer preview"
        frames.append((compose(await snapshot(), label: label, accent: green, keycap: false), 1.8))

        // 3. Scroll to the end.
        let maxScroll = (await js("document.documentElement.scrollHeight - window.innerHeight") as? NSNumber)?
            .doubleValue ?? 0
        if maxScroll > 4 {
            let steps = 16
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                let eased = t * t * (3 - 2 * t)
                _ = await js("window.scrollTo(0, \(maxScroll * eased))")
                try? await Task.sleep(nanoseconds: 60_000_000)
                let last = i == steps
                frames.append((compose(await snapshot(), label: label, accent: green, keycap: false), last ? 2.2 : 0.06))
            }
        }

        writeGIF()
    }

    func writeGIF() {
        guard let dest = CGImageDestinationCreateWithURL(
            outURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { fatalError("cannot create GIF") }
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
        print("wrote \(outURL.path) (\(frames.count) frames)")
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
    let driver = Driver()
    await driver.run()
    exit(0)
}
app.run()
