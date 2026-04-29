//
//  ShikimoriHTML.swift
//  MyShikiPlayer
//
//  Allowlist-based parser for Shikimori `html_body`. Turns the server-
//  rendered HTML into our existing Segment/Inline AST so the same
//  renderer in `FormattedBody`/`InlineFlow` can display it.
//
//  We don't trust the HTML to be safe to render through `WKWebView` /
//  `NSAttributedString(html:)` — both are real browsers under the hood.
//  Instead, this parser walks the DOM with SwiftSoup and only accepts
//  a known set of tags + attributes; anything else is dropped or
//  recursed into as transparent.
//
//  Tags we recognise (everything else is dropped or recursed):
//    Block: <div class="b-spoiler_block">, <div class="b-quote">,
//           <div class="b-replies">, <div class="b-video">,
//           <a class="b-image">, <img>, <blockquote>, <pre>,
//           <h1…h5>, <ul>, <ol>.
//    Inline: <br>, <b>, <strong>, <i>, <em>, <u>, <s>, <strike>, <del>,
//            <code>, <span>, <a class="bubbled b-link" data-attrs="…">,
//            <a class="b-mention bubbled" data-attrs="…">, <a> (other),
//            <img class="smiley">.
//

import Foundation
import SwiftSoup

enum ShikimoriHTML {

    // MARK: - Public API

    /// Parses block-level HTML. Inline content between blocks is emitted
    /// as `Segment.plain(<html-fragment>)` and re-parsed by `parseInlines`
    /// at render time.
    static func parse(_ html: String) -> [ShikimoriText.Segment] {
        guard !html.isEmpty,
              let doc = try? SwiftSoup.parseBodyFragment(html),
              let body = doc.body() else { return [] }
        var out: [ShikimoriText.Segment] = []
        var inlineBuf = ""
        for node in body.getChildNodes() {
            walkBlock(node, segments: &out, inlineBuf: &inlineBuf)
        }
        flushInline(&inlineBuf, into: &out)
        return out
    }

    /// Parses inline-only HTML into a flat `[Inline]` list. Block elements
    /// inside the input are made transparent (their inline children are
    /// promoted to the top level so nothing visible is lost).
    static func parseInlines(_ html: String) -> [ShikimoriText.Inline] {
        guard !html.isEmpty,
              let doc = try? SwiftSoup.parseBodyFragment(html),
              let body = doc.body() else { return [] }
        var inlines: [ShikimoriText.Inline] = []
        for node in body.getChildNodes() {
            walkInline(node, into: &inlines, style: nil)
        }
        return inlines
    }

    // MARK: - Block walker

    private static func walkBlock(
        _ node: Node,
        segments: inout [ShikimoriText.Segment],
        inlineBuf: inout String
    ) {
        if node is TextNode {
            // Preserve entity-escaped form so the inline parser sees the
            // same input SwiftSoup originally consumed.
            inlineBuf.append((try? node.outerHtml()) ?? "")
            return
        }
        guard let element = node as? Element else { return }
        let tag = element.tagName().lowercased()
        let classes = classNames(element)

        switch tag {
        case "div":
            handleDivBlock(element, classes: classes, segments: &segments, inlineBuf: &inlineBuf)
        case "blockquote":
            flushInline(&inlineBuf, into: &segments)
            let inner = (try? element.html()) ?? ""
            if !inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.markdownQuote(inner))
            }
        case "pre":
            flushInline(&inlineBuf, into: &segments)
            let codeText = (try? element.text()) ?? ""
            let lang = inferCodeLanguage(element)
            if !codeText.isEmpty { segments.append(.codeBlock(language: lang, text: codeText)) }
        case "h1", "h2", "h3", "h4", "h5":
            flushInline(&inlineBuf, into: &segments)
            let level = Int(String(tag.dropFirst())) ?? 1
            let inner = (try? element.html()) ?? ""
            if !inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.heading(level: level, text: inner))
            }
        case "ul", "ol":
            flushInline(&inlineBuf, into: &segments)
            let items = element.children().array().compactMap { li -> String? in
                guard li.tagName().lowercased() == "li" else { return nil }
                return try? li.html()
            }
            if !items.isEmpty { segments.append(.list(items)) }
        case "img":
            // Top-level (not smiley) <img> — direct image embed (`[img]URL[/img]`).
            if classes.contains("smiley") {
                inlineBuf.append((try? element.outerHtml()) ?? "")
                return
            }
            flushInline(&inlineBuf, into: &segments)
            if let src = try? element.attr("src"),
               let url = URL(string: src),
               ShikimoriText.isSafeExternalURL(url) {
                segments.append(.image(url: url))
            }
        case "a":
            // `<a class="b-image" data-attrs="{id:N}"><img src="…thumb…"></a>`
            // is a Shikimori-hosted upload (`[image=ID]` BBCode).
            if classes.contains("b-image") {
                flushInline(&inlineBuf, into: &segments)
                if let url = bImageURL(element) {
                    segments.append(.image(url: url))
                }
            } else if let url = anchorAsImageURL(element) {
                // Plain `<a href="…image.jpg">…</a>` at block level — Shikimori
                // doesn't wrap pasted image URLs in `b-image`, so we promote
                // them to a real image embed instead of a red link.
                flushInline(&inlineBuf, into: &segments)
                segments.append(.image(url: url))
            } else {
                inlineBuf.append((try? element.outerHtml()) ?? "")
            }
        case "p":
            // `<p>` is transparent at block level: recurse so anchor-as-image
            // promotion (above) and any nested block constructs surface, while
            // text and inline runs continue to accumulate into `inlineBuf`.
            for child in element.getChildNodes() {
                walkBlock(child, segments: &segments, inlineBuf: &inlineBuf)
            }
        default:
            // Unknown block-context tag — accumulate as inline. The inline
            // parser handles tags it knows, drops the rest.
            inlineBuf.append((try? element.outerHtml()) ?? "")
        }
    }

    private static func handleDivBlock(
        _ element: Element,
        classes: Set<String>,
        segments: inout [ShikimoriText.Segment],
        inlineBuf: inout String
    ) {
        if classes.contains("b-spoiler_block") {
            flushInline(&inlineBuf, into: &segments)
            // Structure: <div class="b-spoiler_block">
            //   <span tabindex="0">title</span>
            //   <div>…content…</div>
            // </div>
            let kids = element.children().array()
            let label = kids.first { $0.tagName().lowercased() == "span" }
                .flatMap { try? $0.text() }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
            let inner: String
            if let last = kids.last, last.tagName().lowercased() == "div", kids.count >= 2 {
                inner = (try? last.html()) ?? ""
            } else {
                inner = (try? element.html()) ?? ""
            }
            segments.append(.spoiler(label: label, content: inner))
            return
        }
        if classes.contains("b-quote") {
            flushInline(&inlineBuf, into: &segments)
            let author = quoteAuthor(element)
            let content = element.children().array().first { kid in
                ((try? kid.classNames().contains("quote-content")) ?? false)
            }
            let inner = (content.flatMap { try? $0.html() }) ?? ""
            if !inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.quote(content: inner, author: author))
            }
            return
        }
        // `b-replies` and `b-video` are kept inline so the renderer styles
        // them the same way as inline mentions / external chips.
        if classes.contains("b-replies") || classes.contains("b-video") {
            inlineBuf.append((try? element.outerHtml()) ?? "")
            return
        }
        // Plain `<div>` — recurse into children at block level.
        for child in element.getChildNodes() {
            walkBlock(child, segments: &segments, inlineBuf: &inlineBuf)
        }
    }

    /// Trims and emits the inline buffer as a `.plain` segment.
    private static func flushInline(_ buf: inout String, into segments: inout [ShikimoriText.Segment]) {
        let trimmed = buf.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { segments.append(.plain(buf)) }
        buf.removeAll(keepingCapacity: true)
    }

    // MARK: - Inline walker

    private static func walkInline(
        _ node: Node,
        into inlines: inout [ShikimoriText.Inline],
        style: ShikimoriText.InlineStyle?
    ) {
        if let text = node as? TextNode {
            let s = text.getWholeText()
            guard !s.isEmpty else { return }
            if let style {
                inlines.append(.styled(text: s, style: style))
            } else {
                inlines.append(.text(s))
            }
            return
        }
        guard let element = node as? Element else { return }
        let tag = element.tagName().lowercased()
        let classes = classNames(element)

        switch tag {
        case "br":
            inlines.append(.text("\n"))
        case "b", "strong":
            recurseStyled(element, into: &inlines, style: style) { $0.bold = true }
        case "i", "em":
            recurseStyled(element, into: &inlines, style: style) { $0.italic = true }
        case "u":
            recurseStyled(element, into: &inlines, style: style) { $0.underline = true }
        case "s", "strike", "del":
            // Inside `<a class="b-mention">` Shikimori uses <s>@</s> for the
            // visible "@" prefix. The mention handler emits "@nick" itself,
            // so we drop this <s> to avoid a double-prefix.
            if isInsideMention(element) { return }
            recurseStyled(element, into: &inlines, style: style) { $0.strikethrough = true }
        case "a":
            handleAnchor(element, classes: classes, into: &inlines)
        case "img":
            handleImg(element, classes: classes, into: &inlines)
        case "code":
            let inner = (try? element.text()) ?? ""
            if !inner.isEmpty { inlines.append(.inlineCode(inner)) }
        case "div" where classes.contains("b-replies"):
            handleReplies(element, into: &inlines)
        case "div", "span", "p":
            // Transparent — recurse into children with same style.
            recurseInlines(element, into: &inlines, style: style)
        default:
            // Unknown inline tag — preserve content by recursing.
            recurseInlines(element, into: &inlines, style: style)
        }
    }

    private static func recurseInlines(
        _ element: Element,
        into inlines: inout [ShikimoriText.Inline],
        style: ShikimoriText.InlineStyle?
    ) {
        for child in element.getChildNodes() {
            walkInline(child, into: &inlines, style: style)
        }
    }

    private static func recurseStyled(
        _ element: Element,
        into inlines: inout [ShikimoriText.Inline],
        style: ShikimoriText.InlineStyle?,
        mutate: (inout ShikimoriText.InlineStyle) -> Void
    ) {
        var next = style ?? ShikimoriText.InlineStyle()
        mutate(&next)
        recurseInlines(element, into: &inlines, style: next)
    }

    // MARK: - Anchor / image / replies

    private static func handleAnchor(
        _ element: Element,
        classes: Set<String>,
        into inlines: inout [ShikimoriText.Inline]
    ) {
        // Comment mention: `<a class="b-mention bubbled" data-attrs="{type:comment,id:N,userId:N,text:Nick}">`
        if classes.contains("b-mention"),
           let attrs = decodeDataAttrs(element),
           let type = attrs["type"] as? String,
           type == "comment",
           let id = attrs["id"] as? Int {
            let userId = attrs["userId"] as? Int
            inlines.append(.commentReference(commentId: id, authorId: userId))
            return
        }
        // Entity link: `<a class="bubbled b-link" data-attrs="{type:anime,id:N,name:…,russian:…}">label</a>`
        if classes.contains("b-link"),
           let attrs = decodeDataAttrs(element),
           let type = attrs["type"] as? String,
           let id = attrs["id"] as? Int {
            let label = (attrs["russian"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (attrs["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? ((try? element.text()).flatMap { $0.isEmpty ? nil : $0 })
                ?? "ссылка"
            if let inline = ShikimoriText.entityInline(kind: type, id: id, label: label) {
                inlines.append(inline)
                return
            }
            // Unknown entity kind — fall through to plain external link below.
        }
        guard let href = try? element.attr("href"), !href.isEmpty else { return }
        let absolute = href.hasPrefix("/") ? "https://shikimori.io" + href : href
        guard let url = URL(string: absolute), ShikimoriText.isSafeExternalURL(url) else { return }
        let label = (try? element.text()) ?? url.absoluteString
        inlines.append(.external(url: url, label: label.isEmpty ? url.absoluteString : label))
    }

    private static func handleImg(
        _ element: Element,
        classes: Set<String>,
        into inlines: inout [ShikimoriText.Inline]
    ) {
        if classes.contains("smiley") {
            // `<img class="smiley" alt=":token:" src="…">`. The token is in
            // the alt attribute; the catalog maps it to a bundled GIF.
            if let alt = try? element.attr("alt"), !alt.isEmpty {
                inlines.append(.smiley(token: alt))
            }
            return
        }
        // Inline avatars / decorative `<img>`: drop. We don't have a
        // convenient way to size random remote images mid-text without
        // breaking line-height; block-level <img> goes through walkBlock
        // separately and gets its own row.
    }

    private static func handleReplies(_ element: Element, into inlines: inout [ShikimoriText.Inline]) {
        var ids: [Int] = []
        let mentions = (try? element.getElementsByClass("b-mention").array()) ?? []
        for mention in mentions {
            if let attrs = decodeDataAttrs(mention), let id = attrs["id"] as? Int {
                ids.append(id)
            }
        }
        if !ids.isEmpty { inlines.append(.replies(ids)) }
    }

    private static func isInsideMention(_ element: Element) -> Bool {
        var cursor: Element? = element.parent()
        while let c = cursor {
            if classNames(c).contains("b-mention") { return true }
            cursor = c.parent()
        }
        return false
    }

    /// SwiftSoup returns an `OrderedSet<String>` and the call throws — wrap it
    /// once so the walkers can use a plain `Set<String>` everywhere.
    private static func classNames(_ element: Element) -> Set<String> {
        guard let names = try? element.classNames() else { return [] }
        return Set(names)
    }

    // MARK: - Helpers

    /// Decodes the HTML-encoded `data-attrs` attribute as JSON.
    /// Shikimori emits it inside double quotes with embedded `&quot;`.
    private static func decodeDataAttrs(_ element: Element) -> [String: Any]? {
        guard let raw = try? element.attr("data-attrs"), !raw.isEmpty else { return nil }
        // SwiftSoup auto-decodes HTML entities when reading attributes,
        // so `raw` is already valid JSON. We still defend against the
        // double-encoded case (`&amp;quot;`) just in case.
        let decoded = raw
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
        guard let data = decoded.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj
    }

    /// Pulls the author nickname out of `<div class="b-quote" data-attrs="UID;CID;Nick">`.
    private static func quoteAuthor(_ element: Element) -> String? {
        guard let attrs = try? element.attr("data-attrs"), !attrs.isEmpty else { return nil }
        let parts = attrs.split(separator: ";", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return nil }
        let nick = parts[2].trimmingCharacters(in: .whitespaces)
        return nick.isEmpty ? nil : nick
    }

    /// Plain `<a href="…image.jpg">…</a>` (no `b-image` class) — when the
    /// href looks like an image (extension or Shikimori `/system/` upload)
    /// AND the anchor's visible text is nothing but the URL itself (or a tiny
    /// emoji/whitespace), we treat it as a block image embed. The text-equals-
    /// href guard prevents promoting a sentence link like
    /// `[posted this](shot.jpg)` into a freestanding image.
    private static func anchorAsImageURL(_ element: Element) -> URL? {
        guard let href = try? element.attr("href"), !href.isEmpty,
              let url = URL(string: href.hasPrefix("/") ? "https://shikimori.io" + href : href),
              ShikimoriText.isSafeExternalURL(url),
              ShikimoriText.isImageURL(url) else { return nil }
        let label = ((try? element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty { return url }
        if label == href || label == url.absoluteString { return url }
        return nil
    }

    /// `<a class="b-image" href="ORIG_URL"><img src="THUMB_URL"></a>` — prefer
    /// the `<a href>` (full-resolution original); fall back to the inner
    /// `<img src>` thumbnail.
    private static func bImageURL(_ element: Element) -> URL? {
        if let href = try? element.attr("href"),
           let url = URL(string: href),
           ShikimoriText.isSafeExternalURL(url) {
            return url
        }
        if let img = (try? element.getElementsByTag("img"))?.first(),
           let src = try? img.attr("src"),
           let url = URL(string: src),
           ShikimoriText.isSafeExternalURL(url) {
            return url
        }
        return nil
    }

    /// `<pre><code class="language-swift">…</code></pre>`.
    private static func inferCodeLanguage(_ element: Element) -> String? {
        guard let code = (try? element.getElementsByTag("code"))?.first(),
              let cls = try? code.attr("class") else { return nil }
        for token in cls.split(separator: " ") where token.hasPrefix("language-") {
            return String(token.dropFirst("language-".count))
        }
        return nil
    }
}
