# Release notes — v2.4

Select this file in Finder and press **Space**. You get the *rendered* document
instead of raw text, with ~~no setup~~ `zero dependencies`. See the [docs](https://example.com).

## Checklist

- [x] Headings, lists, links and inline styles
- [x] Tables, code blocks and quotes
- [ ] Syntax highlighting

## Benchmarks

| File size   | Lines | Render time |
|:------------|------:|------------:|
| README      |    35 |        2 ms |
| Long guide  | 1,680 |       36 ms |

```swift
let renderer = MarkdownRenderer()
let html = renderer.render(markdown)
```

> [!TIP]
> Light and dark mode both follow the system appearance.
