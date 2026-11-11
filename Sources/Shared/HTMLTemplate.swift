import Foundation

enum HTMLTemplate {
    /// Files larger than this are shown as plain text instead of being parsed.
    static let maxRenderedCharacters = 1_000_000

    /// Full HTML document for a Markdown source.
    static func document(markdown: String, title: String, baseDirectory: URL?) -> String {
        if markdown.utf8.count > maxRenderedCharacters {
            let note = "<p><em>This file is too large to render, so it is shown as plain text.</em></p>"
            return page(title: title, body: note + "<pre><code>\(MarkdownRenderer.escape(markdown))</code></pre>")
        }
        let renderer = MarkdownRenderer(imageResolver: LocalImageInliner(baseDirectory: baseDirectory).resolve)
        return page(title: title, body: renderer.render(markdown))
    }

    static func page(title: String, body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light dark">
        <title>\(MarkdownRenderer.escape(title))</title>
        <style>\(css)</style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    static let css = """
    :root {
      color-scheme: light dark;
      --fg: #1f2328; --muted: #59636e; --bg: #ffffff; --border: #d1d9e0; --border-muted: #d1d9e0b3;
      --code-bg: #f6f8fa; --inline-code-bg: #818b981f; --link: #0969da; --mark: #fff8c5;
      --note: #0969da; --tip: #1a7f37; --important: #8250df; --warning: #9a6700; --caution: #d1242f;
      --row-alt: #f6f8fa;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --fg: #e6edf3; --muted: #9198a1; --bg: #0d1117; --border: #3d444d; --border-muted: #3d444db3;
        --code-bg: #151b23; --inline-code-bg: #656c7633; --link: #4493f8; --mark: #bb800926;
        --note: #4493f8; --tip: #3fb950; --important: #ab7df8; --warning: #d29922; --caution: #f85149;
        --row-alt: #151b23;
      }
    }
    * { box-sizing: border-box; }
    html, body { background: var(--bg); color: var(--fg); margin: 0; }
    body {
      font: 16px/1.6 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
      -webkit-font-smoothing: antialiased; word-wrap: break-word;
    }
    .markdown-body { max-width: 920px; margin: 0 auto; padding: 32px 40px 64px; }
    .markdown-body > *:first-child { margin-top: 0 !important; }
    h1, h2, h3, h4, h5, h6 { margin: 24px 0 16px; font-weight: 600; line-height: 1.25; }
    h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--border-muted); }
    h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--border-muted); }
    h3 { font-size: 1.25em; } h4 { font-size: 1em; } h5 { font-size: .875em; }
    h6 { font-size: .85em; color: var(--muted); }
    p, blockquote, ul, ol, dl, table, pre, details, .alert, .table-wrap { margin: 0 0 16px; }
    a { color: var(--link); text-decoration: none; }
    a:hover { text-decoration: underline; }
    strong { font-weight: 600; }
    mark { background: var(--mark); color: inherit; padding: 0 2px; border-radius: 3px; }
    hr { height: 4px; padding: 0; margin: 24px 0; background: var(--border); border: 0; border-radius: 2px; }
    img { max-width: 100%; box-sizing: content-box; }
    ul, ol { padding-left: 2em; }
    li + li { margin-top: .25em; }
    li > ul, li > ol { margin: .25em 0 0; }
    li > p { margin-top: 16px; }
    ul.task-list { list-style: none; padding-left: 1.4em; }
    .task-list-item input { margin: 0 .35em 0 -1.4em; vertical-align: middle; }
    blockquote { padding: 0 1em; color: var(--muted); border-left: .25em solid var(--border); margin-left: 0; }
    blockquote > :last-child, .alert > :last-child { margin-bottom: 0; }
    code, pre, kbd { font-family: ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, monospace; }
    code { font-size: 85%; padding: .2em .4em; background: var(--inline-code-bg); border-radius: 6px; }
    pre {
      position: relative; padding: 16px; overflow: auto; font-size: 85%; line-height: 1.45;
      background: var(--code-bg); border-radius: 6px;
    }
    pre code { padding: 0; background: transparent; font-size: 100%; white-space: pre; border-radius: 0; }
    .code-lang {
      position: absolute; top: 6px; right: 10px; font-size: 11px; color: var(--muted);
      text-transform: lowercase; user-select: none; -webkit-user-select: none;
    }
    pre.front-matter { border: 1px dashed var(--border); }
    kbd {
      display: inline-block; padding: 2px 5px; font-size: 11px; line-height: 10px; color: var(--fg);
      background: var(--code-bg); border: 1px solid var(--border); border-radius: 6px;
      box-shadow: inset 0 -1px 0 var(--border);
    }
    .table-wrap { overflow-x: auto; }
    table { border-spacing: 0; border-collapse: collapse; margin: 0; }
    th, td { padding: 6px 13px; border: 1px solid var(--border); }
    th { font-weight: 600; }
    tbody tr:nth-child(2n) { background: var(--row-alt); }
    .alert { padding: 8px 16px; border-left: .25em solid; }
    .alert-title { font-weight: 600; margin: 0 0 8px; }
    .alert-note { border-color: var(--note); } .alert-note .alert-title { color: var(--note); }
    .alert-tip { border-color: var(--tip); } .alert-tip .alert-title { color: var(--tip); }
    .alert-important { border-color: var(--important); } .alert-important .alert-title { color: var(--important); }
    .alert-warning { border-color: var(--warning); } .alert-warning .alert-title { color: var(--warning); }
    .alert-caution { border-color: var(--caution); } .alert-caution .alert-title { color: var(--caution); }
    .footnote-ref { font-size: .75em; color: var(--link); }
    details summary { cursor: pointer; }
    @media print {
      .markdown-body { max-width: none; padding: 0; }
      pre { white-space: pre-wrap; }
      pre code { white-space: pre-wrap; }
    }
    """
}
