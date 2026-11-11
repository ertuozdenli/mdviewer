import Foundation

/// Dependency-free Markdown → HTML renderer.
/// Supports CommonMark basics plus GitHub extras: tables, task lists, strikethrough,
/// fenced code, autolinks, front matter, alerts ([!NOTE] etc.) and footnote markers.
final class MarkdownRenderer {
    typealias ImageResolver = (String) -> String?

    private let imageResolver: ImageResolver?
    private var refs: [String: (url: String, title: String)] = [:]
    private var usedSlugs: [String: Int] = [:]
    private var store: [String] = []
    private var deadline = Date.distantFuture

    /// Inline formatting is skipped for text longer than this, and once the time budget is spent,
    /// so a malformed or hostile file can't stall the preview.
    private static let maxInlineLength = 100_000
    private static let timeBudget: TimeInterval = 2

    init(imageResolver: ImageResolver? = nil) {
        self.imageResolver = imageResolver
    }

    // MARK: - Public

    func render(_ markdown: String) -> String {
        refs = [:]; usedSlugs = [:]; store = []
        deadline = Date().addingTimeInterval(Self.timeBudget)
        var text = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        var lines = text.components(separatedBy: "\n").map { $0.replacingOccurrences(of: "\t", with: "    ") }

        var out = ""
        if let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---",
           let end = lines.dropFirst().firstIndex(where: {
               let t = $0.trimmingCharacters(in: .whitespaces); return t == "---" || t == "..."
           }) {
            let fm = lines[1..<end].joined(separator: "\n")
            if !fm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out += "<pre class=\"front-matter\"><code>\(Self.escape(fm))</code></pre>\n"
            }
            lines = Array(lines[(end + 1)...])
        }
        lines = extractReferences(lines)
        out += renderBlocks(lines, tight: false)
        return out
    }

    // MARK: - Regex helpers

    private static var cache: [String: NSRegularExpression] = [:]
    private static let cacheLock = NSLock()

    private static func regex(_ p: String) -> NSRegularExpression {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let r = cache[p] { return r }
        let r = try! NSRegularExpression(pattern: p, options: [])
        cache[p] = r
        return r
    }

    /// Returns capture groups (index 0 = whole match) or nil.
    private static func match(_ pattern: String, _ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = regex(pattern).firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map {
            let r = m.range(at: $0); return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    private static func replace(_ s: String, _ pattern: String, _ f: ([String]) -> String) -> String {
        let ns = s as NSString
        let matches = regex(pattern).matches(in: s, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return s }
        var result = ""
        var last = 0
        for m in matches {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let groups = (0..<m.numberOfRanges).map { i -> String in
                let r = m.range(at: i); return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            result += f(groups)
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Line classification

    private func isBlank(_ l: String) -> Bool { l.allSatisfy { $0 == " " } }

    private func indent(_ l: String) -> Int { l.prefix { $0 == " " }.count }

    private func dropIndent(_ l: String, _ n: Int) -> String {
        let k = min(n, indent(l)); return String(l.dropFirst(k))
    }

    private struct Fence { let char: Character; let len: Int; let indent: Int; let info: String }

    private func fence(_ l: String) -> Fence? {
        guard let g = Self.match(#"^( {0,3})(`{3,}|~{3,})\s*(.*)$"#, l) else { return nil }
        if g[2].first == "`" && g[3].contains("`") { return nil }
        return Fence(char: g[2].first!, len: g[2].count, indent: g[1].count, info: g[3].trimmingCharacters(in: .whitespaces))
    }

    private func closesFence(_ l: String, _ f: Fence) -> Bool {
        guard let g = Self.match(#"^ {0,3}(`{3,}|~{3,})\s*$"#, l) else { return false }
        return g[1].first == f.char && g[1].count >= f.len
    }

    private func heading(_ l: String) -> (Int, String)? {
        guard let g = Self.match(#"^ {0,3}(#{1,6})(?:[ ]+(.*?))?[ ]*$"#, l) else { return nil }
        var text = g[2]
        text = Self.replace(text, #"(?:^|[ ]+)#+[ ]*$"#) { _ in "" }
        return (g[1].count, text)
    }

    private func isHR(_ l: String) -> Bool {
        Self.match(#"^ {0,3}(?:(?:\*[ ]*){3,}|(?:-[ ]*){3,}|(?:_[ ]*){3,})$"#, l) != nil
    }

    private func quote(_ l: String) -> String? {
        Self.match(#"^ {0,3}> ?(.*)$"#, l)?[1]
    }

    private struct ListMarker {
        let ordered: Bool; let delim: String; let start: Int; let contentIndent: Int; let rest: String; let indent: Int
    }

    private func listMarker(_ l: String) -> ListMarker? {
        guard let g = Self.match(#"^( {0,3})([-*+]|(\d{1,9})([.)]))(?:( +)(.*))?$"#, l) else { return nil }
        let ind = g[1].count
        let ordered = !g[3].isEmpty
        let markerLen = g[2].count
        let spaces = g[5].count
        var rest = g[6]
        var contentIndent = ind + markerLen + max(spaces, 1)
        if spaces > 4 { // indented code inside item: content starts after one space
            contentIndent = ind + markerLen + 1
            rest = String(repeating: " ", count: spaces - 1) + rest
        }
        return ListMarker(ordered: ordered, delim: ordered ? g[4] : g[2], start: Int(g[3]) ?? 1,
                          contentIndent: contentIndent, rest: rest, indent: ind)
    }

    private static let blockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "center", "details", "dialog", "div", "dl", "dd", "dt",
        "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header",
        "hr", "img", "li", "main", "nav", "ol", "p", "picture", "pre", "section", "summary", "table", "tbody",
        "td", "tfoot", "th", "thead", "tr", "ul", "video", "audio", "br", "source", "a",
    ]

    private func htmlBlockStart(_ l: String) -> Bool {
        if Self.match(#"^ {0,3}<!--"#, l) != nil { return true }
        guard let g = Self.match(#"^ {0,3}</?([A-Za-z][A-Za-z0-9-]*)(?:\s|/?>|$)"#, l) else { return false }
        let tag = g[1].lowercased()
        // <a> only starts a block when it's alone on the line-ish (common in READMEs: <a href><img></a>)
        if tag == "a" { return Self.match(#"^ {0,3}<a\b[^>]*>\s*<img"#, l) != nil }
        return Self.blockTags.contains(tag)
    }

    private func isTableDelimiter(_ l: String) -> Bool {
        l.contains("-") && Self.match(#"^ {0,3}\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)*\|?\s*$"#, l) != nil
    }

    /// Whether a line can interrupt a paragraph.
    private func startsBlock(_ l: String) -> Bool {
        if fence(l) != nil || heading(l) != nil || isHR(l) || quote(l) != nil || htmlBlockStart(l) { return true }
        if let m = listMarker(l), !m.rest.trimmingCharacters(in: .whitespaces).isEmpty, !m.ordered || m.start == 1 {
            return true
        }
        return false
    }

    // MARK: - References

    private func extractReferences(_ lines: [String]) -> [String] {
        var out: [String] = []
        var openFence: Fence?
        for l in lines {
            if let f = openFence {
                if closesFence(l, f) { openFence = nil }
                out.append(l); continue
            }
            if let f = fence(l) { openFence = f; out.append(l); continue }
            if let g = Self.match(#"^ {0,3}\[([^\]^][^\]]*)\]:\s*<?([^\s>]+)>?(?:\s+["'(](.*)["')])?\s*$"#, l) {
                let key = g[1].lowercased()
                if refs[key] == nil { refs[key] = (g[2], g[3]) }
                continue
            }
            out.append(l)
        }
        return out
    }

    // MARK: - Blocks

    private func renderBlocks(_ lines: [String], tight: Bool) -> String {
        var out = ""
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if isBlank(line) { i += 1; continue }

            // Fenced code
            if let f = fence(line) {
                var code: [String] = []
                var closed = false
                i += 1
                while i < lines.count {
                    if closesFence(lines[i], f) { i += 1; closed = true; break }
                    code.append(dropIndent(lines[i], f.indent)); i += 1
                }
                if !closed { while let last = code.last, isBlank(last) { code.removeLast() } }
                out += codeBlock(code.joined(separator: "\n"), lang: f.info.split(separator: " ").first.map(String.init) ?? "")
                continue
            }

            // Indented code
            if indent(line) >= 4 {
                var code: [String] = []
                while i < lines.count, isBlank(lines[i]) || indent(lines[i]) >= 4 {
                    code.append(dropIndent(lines[i], 4)); i += 1
                }
                while let last = code.last, isBlank(last) { code.removeLast() }
                out += codeBlock(code.joined(separator: "\n"), lang: "")
                continue
            }

            if let (level, text) = heading(line) {
                out += headingTag(level, text); i += 1; continue
            }

            if isHR(line) { out += "<hr>\n"; i += 1; continue }

            // Blockquote
            if quote(line) != nil {
                var inner: [String] = []
                while i < lines.count {
                    if let q = quote(lines[i]) {
                        inner.append(q); i += 1
                    } else if !isBlank(lines[i]), let last = inner.last, !isBlank(last), !startsBlock(lines[i]) {
                        inner.append(lines[i]); i += 1 // lazy continuation
                    } else { break }
                }
                out += blockquote(inner)
                continue
            }

            // List
            if listMarker(line) != nil {
                let (html, next) = parseList(lines, i)
                out += html; i = next
                continue
            }

            // HTML block
            if htmlBlockStart(line) {
                var raw: [String] = []
                let isComment = line.trimmingCharacters(in: .whitespaces).hasPrefix("<!--")
                while i < lines.count {
                    if !isComment && isBlank(lines[i]) { break }
                    raw.append(lines[i]); i += 1
                    if isComment && raw.last!.contains("-->") { break }
                }
                out += rewriteImages(raw.joined(separator: "\n")) + "\n"
                continue
            }

            // Table
            if line.contains("|"), i + 1 < lines.count, isTableDelimiter(lines[i + 1]) {
                let (html, next) = parseTable(lines, i)
                out += html; i = next
                continue
            }

            // Paragraph (with setext heading detection)
            var para = [line]
            i += 1
            var setext = 0
            while i < lines.count {
                let l = lines[i]
                if isBlank(l) { break }
                if Self.match(#"^ {0,3}=+\s*$"#, l) != nil { setext = 1; i += 1; break }
                if Self.match(#"^ {0,3}-+\s*$"#, l) != nil { setext = 2; i += 1; break }
                if startsBlock(l) { break }
                if l.contains("|"), i + 1 < lines.count, isTableDelimiter(lines[i + 1]) { break }
                para.append(l); i += 1
            }
            let text = para.map { $0.drop { $0 == " " } }.joined(separator: "\n")
                .trimmingCharacters(in: .whitespaces)
            if setext > 0 {
                out += headingTag(setext, text)
            } else if tight {
                out += inline(text) + "\n"
            } else {
                out += "<p>" + inline(text) + "</p>\n"
            }
        }
        return out
    }

    private func codeBlock(_ code: String, lang: String) -> String {
        let cls = lang.isEmpty ? "" : " class=\"language-\(Self.escape(lang))\""
        let label = lang.isEmpty ? "" : "<span class=\"code-lang\">\(Self.escape(lang))</span>"
        return "<pre>\(label)<code\(cls)>\(Self.escape(code))</code></pre>\n"
    }

    private func headingTag(_ level: Int, _ text: String) -> String {
        let html = inline(text)
        let plain = Self.replace(html, #"<[^>]+>"#) { _ in "" }
            .replacingOccurrences(of: "&amp;", with: "&")
        var slug = plain.lowercased().unicodeScalars.compactMap { c -> String? in
            if CharacterSet.alphanumerics.contains(c) || c == "_" || c == "-" { return String(c) }
            if c == " " { return "-" }
            return nil
        }.joined()
        if let n = usedSlugs[slug] { usedSlugs[slug] = n + 1; slug += "-\(n + 1)" } else { usedSlugs[slug] = 0 }
        return "<h\(level) id=\"\(Self.escape(slug))\">\(html)</h\(level)>\n"
    }

    private func blockquote(_ inner: [String]) -> String {
        // GitHub alerts: > [!NOTE]
        if let first = inner.first,
           let g = Self.match(#"^\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$"#, first.uppercased()) {
            let kind = g[1].lowercased()
            let title = kind.prefix(1).uppercased() + kind.dropFirst()
            return "<div class=\"alert alert-\(kind)\"><p class=\"alert-title\">\(title)</p>\n"
                + renderBlocks(Array(inner.dropFirst()), tight: false) + "</div>\n"
        }
        return "<blockquote>\n" + renderBlocks(inner, tight: false) + "</blockquote>\n"
    }

    private func parseList(_ lines: [String], _ start: Int) -> (String, Int) {
        let first = listMarker(lines[start])!
        var items: [[String]] = []
        var current = [first.rest]
        var contentIndent = first.contentIndent
        var sawBlank = false
        var loose = false
        var i = start + 1

        while i < lines.count {
            let l = lines[i]
            if isBlank(l) { current.append(""); sawBlank = true; i += 1; continue }
            let ind = indent(l)
            if ind >= contentIndent {
                current.append(dropIndent(l, contentIndent)); sawBlank = false; i += 1; continue
            }
            if let m = listMarker(l), m.ordered == first.ordered, m.delim == first.delim, !isHR(l) {
                if sawBlank { loose = true }
                items.append(current)
                current = [m.rest]; contentIndent = m.contentIndent; sawBlank = false; i += 1
                continue
            }
            if !sawBlank, !startsBlock(l), !(listMarker(l) != nil) {
                current.append(String(l.drop { $0 == " " })); i += 1; continue // lazy continuation
            }
            break
        }
        items.append(current)

        // Trim trailing blank lines & detect internal blank lines at item level
        items = items.map { item in
            var it = item
            while let last = it.last, isBlank(last), it.count > 1 { it.removeLast() }
            return it
        }
        if !loose {
            outer: for item in items {
                var inFence: Fence?
                for (k, l) in item.enumerated() {
                    if let f = inFence { if closesFence(l, f) { inFence = nil }; continue }
                    if let f = fence(l) { inFence = f; continue }
                    if isBlank(l), k + 1 < item.count, indent(item[k + 1]) == 0, !isBlank(item[k + 1]),
                       k > 0, listMarker(item[k - 1]) == nil || indent(item[k - 1]) == 0 {
                        // blank between two top-level blocks of the item
                        if listMarker(item[k + 1]) == nil { loose = true; break outer }
                    }
                }
            }
        }

        let tag = first.ordered ? "ol" : "ul"
        let startAttr = first.ordered && first.start != 1 ? " start=\"\(first.start)\"" : ""
        let isTaskList = items.allSatisfy { Self.match(#"^\[[ xX]\]\s"#, $0.first ?? "") != nil }
        var out = "<\(tag)\(startAttr)\(isTaskList ? " class=\"task-list\"" : "")>\n"
        for var item in items {
            var prefix = ""
            var cls = ""
            if let g = Self.match(#"^\[([ xX])\]\s+(.*)$"#, item[0]) {
                let checked = g[1] != " "
                prefix = "<input type=\"checkbox\" disabled\(checked ? " checked" : "")> "
                cls = " class=\"task-list-item\""
                item[0] = g[2]
            }
            var inner = renderBlocks(item, tight: !loose).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                if inner.hasPrefix("<p>") { inner = "<p>" + prefix + inner.dropFirst(3) } else { inner = prefix + inner }
            }
            out += "<li\(cls)>\(inner)</li>\n"
        }
        out += "</\(tag)>\n"
        return (out, i)
    }

    private func splitRow(_ row: String) -> [String] {
        var s = row.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") && !s.hasSuffix("\\|") { s.removeLast() }
        var cells: [String] = []
        var cur = ""
        var inCode = false
        var prev: Character = " "
        for c in s {
            if c == "`" { inCode.toggle() }
            if c == "|" && !inCode && prev != "\\" {
                cells.append(cur); cur = ""
            } else if c == "|" && prev == "\\" {
                cur.removeLast(); cur.append("|")
            } else {
                cur.append(c)
            }
            prev = c
        }
        cells.append(cur)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func parseTable(_ lines: [String], _ start: Int) -> (String, Int) {
        let header = splitRow(lines[start])
        let aligns: [String] = splitRow(lines[start + 1]).map { c in
            let l = c.hasPrefix(":"), r = c.hasSuffix(":")
            return l && r ? "center" : r ? "right" : l ? "left" : ""
        }
        func cellTag(_ t: String, _ idx: Int, _ content: String) -> String {
            let a = idx < aligns.count && !aligns[idx].isEmpty ? " style=\"text-align:\(aligns[idx])\"" : ""
            return "<\(t)\(a)>\(inline(content))</\(t)>"
        }
        var out = "<div class=\"table-wrap\"><table>\n<thead><tr>"
        for (k, h) in header.enumerated() { out += cellTag("th", k, h) }
        out += "</tr></thead>\n<tbody>\n"
        var i = start + 2
        while i < lines.count, !isBlank(lines[i]), lines[i].contains("|") || !startsBlock(lines[i]) {
            if startsBlock(lines[i]) { break }
            var cells = splitRow(lines[i])
            if cells.count < header.count { cells += Array(repeating: "", count: header.count - cells.count) }
            out += "<tr>" + cells.prefix(header.count).enumerated().map { cellTag("td", $0.offset, $0.element) }.joined() + "</tr>\n"
            i += 1
        }
        out += "</tbody></table></div>\n"
        return (out, i)
    }

    // MARK: - Inline

    private func ph(_ html: String) -> String {
        store.append(html)
        return "\u{E000}\(store.count - 1)\u{E001}"
    }

    private func resolvePlaceholders(_ s: String) -> String {
        var t = s
        var guardCount = 0
        while t.contains("\u{E000}") && guardCount < 20 {
            t = Self.replace(t, "\u{E000}(\\d+)\u{E001}") { g in
                let idx = Int(g[1])!; return idx < self.store.count ? self.store[idx] : ""
            }
            guardCount += 1
        }
        return t
    }

    private func inline(_ s: String) -> String {
        resolvePlaceholders(inlineRaw(s))
    }

    private func attr(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
    }

    private func imageSrc(_ src: String) -> String {
        imageResolver?(src) ?? src
    }

    /// Neutralises raw HTML tags that can run code, load documents or navigate.
    private func filterTags(_ html: String) -> String {
        Self.replace(html, #"(?i)<(?=/?(?:script|iframe|frame|frameset|object|embed|applet|meta|link|base|form|style|title|textarea|xmp|noembed|noframes|plaintext)(?:[\s/>]|$))"#) { _ in "&lt;" }
    }

    private func rewriteImages(_ rawHTML: String) -> String {
        let html = filterTags(rawHTML)
        guard imageResolver != nil else { return html }
        return Self.replace(html, #"(<img\b[^>]*?\bsrc\s*=\s*)(["'])([^"']+)\2"#) { g in
            g[1] + g[2] + self.attr(self.imageSrc(g[3])) + g[2]
        }
    }

    private func imageTag(_ alt: String, _ src: String, _ title: String) -> String {
        let t = title.isEmpty ? "" : " title=\"\(attr(title))\""
        return "<img src=\"\(attr(imageSrc(src)))\" alt=\"\(attr(alt))\"\(t)>"
    }

    private func linkTag(_ textHTML: String, _ href: String, _ title: String) -> String {
        let t = title.isEmpty ? "" : " title=\"\(attr(title))\""
        return "<a href=\"\(attr(href))\"\(t)>\(textHTML)</a>"
    }

    private func inlineRaw(_ s: String) -> String {
        if s.utf16.count > Self.maxInlineLength || Date() > deadline { return Self.escape(s) }
        var t = s

        // Code spans
        t = Self.replace(t, #"(?<!`)(`+)(?!`)([\s\S]{0,5000}?[^`])\1(?!`)"#) { g in
            var c = g[2].replacingOccurrences(of: "\n", with: " ")
            if c.count >= 2, c.hasPrefix(" "), c.hasSuffix(" "), c.trimmingCharacters(in: .whitespaces) != "" {
                c = String(c.dropFirst().dropLast())
            }
            return self.ph("<code>\(Self.escape(c))</code>")
        }

        // Backslash escapes
        t = Self.replace(t, ##"\\([!"#$%&'()*+,\-./:;<=>?@\[\\\]^_`{|}~])"##) { g in self.ph(Self.escape(g[1])) }

        // Autolinks <https://…> and <mail@x.y>
        t = Self.replace(t, #"<((?:https?|ftp)://[^>\s]+)>"#) { g in self.ph(self.linkTag(Self.escape(g[1]), g[1], "")) }
        t = Self.replace(t, #"<([^@\s<>]+@[^@\s<>]+\.[^@\s<>]+)>"#) { g in
            self.ph(self.linkTag(Self.escape(g[1]), "mailto:" + g[1], ""))
        }

        // Raw inline HTML
        t = Self.replace(t, #"<!--[\s\S]*?-->|</?[A-Za-z][A-Za-z0-9-]*(?:\s+[A-Za-z_:][\w:.-]*(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*\s*/?>"#) { g in
            self.ph(self.rewriteImages(g[0]))
        }

        // Images
        t = Self.replace(t, #"!\[([^\]]{0,1000})\]\(\s*<?([^()\s>]{0,2000}(?:\([^()\s]{0,500}\)[^()\s>]{0,2000})*)>?(?:\s+["']([^"']{0,500})["'])?\s*\)"#) { g in
            self.ph(self.imageTag(g[1], g[2], g[3]))
        }
        t = Self.replace(t, #"!\[([^\]]{0,1000})\]\[([^\]]{0,500})\]"#) { g in
            let key = (g[2].isEmpty ? g[1] : g[2]).lowercased()
            guard let r = self.refs[key] else { return g[0] }
            return self.ph(self.imageTag(g[1], r.url, r.title))
        }

        // Footnote refs
        t = Self.replace(t, #"\[\^([^\]\s]+)\]"#) { g in
            self.ph("<sup class=\"footnote-ref\">\(Self.escape(g[1]))</sup>")
        }

        // Inline links
        t = Self.replace(t, #"\[((?:[^\[\]]|\[[^\[\]]{0,500}\]){0,1000})\]\(\s*<?([^()\s>]{0,2000}(?:\([^()\s]{0,500}\)[^()\s>]{0,2000})*)>?(?:\s+["']([^"']{0,500})["'])?\s*\)"#) { g in
            self.ph(self.linkTag(self.inlineRaw(g[1]), g[2], g[3]))
        }
        // Reference links [text][ref], [text][], [ref]
        t = Self.replace(t, #"\[((?:[^\[\]]|\[[^\[\]]{0,500}\]){1,1000})\](?:\[([^\]]{0,500})\])?"#) { g in
            let key = (g[2].isEmpty ? g[1] : g[2]).lowercased()
            guard let r = self.refs[key] else { return g[0] }
            return self.ph(self.linkTag(self.inlineRaw(g[1]), r.url, r.title))
        }

        // Bare URLs (GFM autolink extension)
        t = Self.replace(t, #"(?<![\w/"'=])((?:https?://|www\.)[^\s<>\x{E000}]*[^\s<>\x{E000}.,:;!?"')\]*_])"#) { g in
            let href = g[1].hasPrefix("www.") ? "http://" + g[1] : g[1]
            return self.ph(self.linkTag(Self.escape(g[1]), href, ""))
        }

        // Escape remaining HTML (keep existing entities)
        t = Self.replace(t, #"&(?!#?[A-Za-z0-9]+;)"#) { _ in "&amp;" }
        t = t.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")

        // Emphasis
        t = Self.replace(t, #"\*\*\*(?!\s)([\s\S]{1,1000}?)(?<!\s)\*\*\*"#) { g in "<strong><em>\(g[1])</em></strong>" }
        t = Self.replace(t, #"\*\*(?!\s)([\s\S]{1,1000}?)(?<!\s)\*\*"#) { g in "<strong>\(g[1])</strong>" }
        t = Self.replace(t, #"(?<!\w)__(?!\s)([\s\S]{1,1000}?)(?<!\s)__(?!\w)"#) { g in "<strong>\(g[1])</strong>" }
        t = Self.replace(t, #"\*(?![\s*])([\s\S]{1,1000}?)(?<![\s*])\*"#) { g in "<em>\(g[1])</em>" }
        t = Self.replace(t, #"(?<!\w)_(?![\s_])([\s\S]{1,1000}?)(?<![\s_])_(?!\w)"#) { g in "<em>\(g[1])</em>" }
        t = Self.replace(t, #"~~(?!\s)([\s\S]{1,1000}?)(?<!\s)~~"#) { g in "<del>\(g[1])</del>" }
        t = Self.replace(t, #"==(?![\s=])([\s\S]{1,1000}?)(?<![\s=])=="#) { g in "<mark>\(g[1])</mark>" }

        // Hard line breaks
        t = Self.replace(t, #"(?: {2,}|\\)\n"#) { _ in "<br>\n" }

        return t
    }
}

/// Inlines local images (relative to the Markdown file) as data: URIs.
struct LocalImageInliner {
    let baseDirectory: URL?

    func resolve(_ src: String) -> String? {
        guard let base = baseDirectory else { return nil }
        let lower = src.lowercased()
        if lower.contains("://") || lower.hasPrefix("data:") || lower.hasPrefix("#") || lower.hasPrefix("mailto:") {
            return nil
        }
        var path = src
        if let q = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = String(path[..<q]) }
        path = path.removingPercentEncoding ?? path
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size < 25_000_000,
              let data = try? Data(contentsOf: url) else { return nil }
        let mime: String
        switch url.pathExtension.lowercased() {
        case "png": mime = "image/png"
        case "jpg", "jpeg": mime = "image/jpeg"
        case "gif": mime = "image/gif"
        case "svg": mime = "image/svg+xml"
        case "webp": mime = "image/webp"
        case "heic": mime = "image/heic"
        case "bmp": mime = "image/bmp"
        case "ico": mime = "image/x-icon"
        case "tif", "tiff": mime = "image/tiff"
        default: mime = "application/octet-stream"
        }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}
