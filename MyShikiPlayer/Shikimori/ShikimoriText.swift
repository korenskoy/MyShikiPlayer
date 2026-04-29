//
//  ShikimoriText.swift
//  MyShikiPlayer
//
//  Helper for rendering text from Shikimori. Shikimori returns two formats:
//  - `body` (BBCode: `[b]`, `[url]`, `[anime=123]Name[/anime]`, `[spoiler]`…)
//  - `html_body` (HTML: `<a>`, `<b>`, `<br>`, spoilers inside `<div class="b-spoiler">`)
//
//  For previews / simple display we reduce to plain text via `toPlain`.
//  For rich rendering (FormattedBody) — `segments` + `parseInlines`,
//  which preserve entity links (`[anime=N]`, `[url]`) so that an
//  AttributedString with clickable regions can be built.
//

import Foundation

enum ShikimoriText {
    /// Allowlist for clickable external URLs that came from user-generated
    /// content (forum BBCode `[url]`, `[img]`, etc). Anything outside
    /// `http`/`https`/`mailto` is rejected before it can become a clickable
    /// link or be passed to `NSWorkspace.open`. The internal `myshiki://`
    /// scheme is handled separately and is never built from user input.
    static func isSafeExternalURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }

    /// Heuristic for "this URL points at an image we can render inline".
    /// Two signals: a known image extension on the path, or a Shikimori-hosted
    /// `/system/...` upload (user images on shikimori.io/.one/.me — they always
    /// resolve to a JPEG/PNG even though the extension is sometimes uppercase
    /// or wrapped in a query string).
    static func isImageURL(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let exts = [".jpg", ".jpeg", ".png", ".gif", ".webp"]
        if exts.contains(where: { path.hasSuffix($0) }) { return true }
        if let host = url.host?.lowercased(),
           host == "shikimori.io" || host == "shikimori.one" || host == "shikimori.me",
           path.hasPrefix("/system/") {
            return true
        }
        return false
    }

    /// Coarse BB-code stripping: keeps the content, removes the tags themselves.
    /// Used in `toPlain` (previews) — the caller expects the result without
    /// trailing whitespace / newlines.
    static func stripBBCode(_ input: String) -> String {
        stripBBCodeMarkers(input).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Same as `stripBBCode`, but WITHOUT trimming the edges. Needed for
    /// parsing inline fragments: whitespace and newlines between links are
    /// significant (otherwise text sticks to a look-alike link).
    private static func stripBBCodeMarkers(_ input: String) -> String {
        var text = input
        text = text.replacingOccurrences(
            of: #"\[(character|person|anime|manga|ranobe)=\d+\]"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\[url(=[^\]]*)?\]"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(
            of: #"\[/?(b|i|u|s|url|character|person|anime|manga|ranobe|spoiler|quote|div|size|color|center|right)(=[^\]]*)?\]"#,
            with: "",
            options: .regularExpression
        )
        text = text.replacingOccurrences(of: "[br]", with: "\n")
        text = text.replacingOccurrences(of: "[hr]", with: "\n\n")
        text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        return text
    }

    /// Flat html → text: strips tags, decodes basic entities.
    static func stripHTML(_ input: String) -> String {
        var text = input
        // Replacements before tag stripping — to preserve line breaks.
        text = text.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        // Strip all remaining tags.
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        // Common HTML entities.
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;",  with: "&")
        text = text.replacingOccurrences(of: "&lt;",   with: "<")
        text = text.replacingOccurrences(of: "&gt;",   with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;",  with: "'")
        text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the most readable plain text: strip HTML if the input looks
    /// like HTML, otherwise BB-code. Safe for both cases.
    static func toPlain(_ input: String?) -> String {
        guard let input, !input.isEmpty else { return "" }
        if input.contains("<") && input.contains(">") {
            return stripHTML(input)
        }
        return stripBBCode(input)
    }

    // MARK: - Segments

    /// A segment of a formatted body: plain text, spoiler, quote, or one of
    /// the Markdown block constructs Shikimori supports (`#…#####` headings,
    /// `> quote`, fenced ` ``` ` blocks, and `- bullet` lists).
    /// Content of `plain` / `spoiler` / `quote` is still raw BBCode and is
    /// later parsed into `[Inline]` via `parseInlines`; `heading` / `markdownQuote`
    /// content is also further parsed inline; `codeBlock` and `list` are rendered
    /// verbatim (no inline parsing).
    enum Segment: Equatable {
        case plain(String)
        /// Shikimori spoilers carry a clickable title (`<span tabindex="0">`)
        /// alongside the hidden content. We preserve both so the renderer
        /// can label the toggle ("а если чут-чут напряжет мускулы?") and
        /// match the web client; `label` is nil when the BBCode `[spoiler]`
        /// form was used without an explicit label.
        case spoiler(label: String?, content: String)
        /// `[quote=USER_ID;USERNAME[;COMMENT_ID]]…[/quote]` — `author` carries
        /// the second attribute component (username) when present.
        case quote(content: String, author: String?)
        /// Markdown heading: `level` is 1…5 (h1…h5).
        case heading(level: Int, text: String)
        /// Markdown blockquote: `> line` (one or more consecutive lines).
        case markdownQuote(String)
        /// Fenced code block: ` ```lang…``` `. `language` is nil for ` ``` ` without a label.
        case codeBlock(language: String?, text: String)
        /// Markdown unordered list: `- item` (one or more consecutive lines).
        case list([String])
        /// Image embedded in the body. The HTML parser already resolves
        /// `<a class="b-image">` and `<img>` to direct URLs.
        case image(url: URL)
    }

    /// Inline-text styling extracted from `[b][i][u][s]` and `[color=…]`.
    /// Multiple flags can stack on a single run because we treat each tag as
    /// independent — nested combinations like `[b][i]X[/i][/b]` collapse to a
    /// single `.styled` with both `bold` and `italic` only when the tags
    /// share their range; otherwise the inner tag's text is taken verbatim.
    struct InlineStyle: Equatable {
        var bold: Bool = false
        var italic: Bool = false
        var underline: Bool = false
        var strikethrough: Bool = false
        /// Hex string as written in BBCode (`#RRGGBB` or `#RGB`); the renderer
        /// parses it on demand.
        var colorHex: String?
    }

    /// Inline fragment of a plain segment: either text, or a link to a
    /// Shikimori entity ([anime=N], [manga=N], …), or an external URL ([url]…[/url]),
    /// or a smiley shortcode (e.g. `:ololo:`, `:-D`, `+_+`),
    /// or a forum reference ([comment=N;A] / [replies=N,N,…]),
    /// or a styled text run (`[b][i][u][s][color=…]`).
    enum Inline: Equatable {
        case text(String)
        case anime(id: Int, name: String)
        case manga(id: Int, name: String)
        case ranobe(id: Int, name: String)
        case character(id: Int, name: String)
        case person(id: Int, name: String)
        case user(id: Int, name: String)
        case external(url: URL, label: String)
        case smiley(token: String)
        /// `[comment=COMMENT_ID(;AUTHOR_ID)?]` — a reference to another comment
        /// in the same topic, optionally tagged with the addressee's user id.
        case commentReference(commentId: Int, authorId: Int?)
        /// `<div class="b-replies">` — comment ids replying to this one.
        /// Author nicknames are resolved at render time via `CommentResolvers`.
        case replies([Int])
        /// `<b>…</b>` / `<i>…</i>` / `<u>…</u>` / `<s>…</s>` / `<span style="color:…">`.
        /// `text` is the content of the styled run (recursing nested style
        /// tags is handled by the parser, not the renderer).
        case styled(text: String, style: InlineStyle)
        /// `<code>…</code>` — monospaced inline run.
        case inlineCode(String)
    }

    /// Builds an entity-link `Inline` from a kind/id/label triple. Returns
    /// nil for an unknown kind so the caller can fall back to a plain link.
    static func entityInline(kind: String, id: Int, label: String) -> Inline? {
        switch kind {
        case "anime":     return .anime(id: id, name: label)
        case "manga":     return .manga(id: id, name: label)
        case "ranobe":    return .ranobe(id: id, name: label)
        case "character": return .character(id: id, name: label)
        case "person":    return .person(id: id, name: label)
        case "user":      return .user(id: id, name: label)
        default:          return nil
        }
    }

    /// Parses a raw body into segments. Always goes through `ShikimoriHTML`
    /// because the renderer expects the resolved-by-server format. The
    /// BBCode `body` is only used as a last-resort fallback (Shikimori
    /// almost always returns both): we strip its markup down to plain text
    /// rather than re-implement a second parser.
    static func segments(_ input: String?) -> [Segment] {
        guard let raw = input, !raw.isEmpty else { return [] }
        if looksLikeHTML(raw) {
            return ShikimoriHTML.parse(raw)
        }
        let plain = stripBBCode(raw)
        return plain.isEmpty ? [] : [.plain(plain)]
    }

    /// Parses inline content into `[Inline]`. Same routing as `segments`.
    static func parseInlines(_ raw: String) -> [Inline] {
        guard !raw.isEmpty else { return [] }
        if looksLikeHTML(raw) {
            return ShikimoriHTML.parseInlines(raw)
        }
        let plain = stripBBCode(raw)
        return plain.isEmpty ? [] : [.text(plain)]
    }

    /// Heuristic: server-rendered HTML always has at least one `<tag>` form.
    /// BBCode bodies can contain `<` / `>` characters but not that shape,
    /// so this is enough to disambiguate.
    private static func looksLikeHTML(_ raw: String) -> Bool {
        guard raw.contains("<"), raw.contains(">") else { return false }
        return raw.range(of: #"<[a-zA-Z/!][^>]*>"#, options: .regularExpression) != nil
    }

}

extension String {
    /// Single project-wide helper used across the BBCode/Markdown stack and
    /// the topic UI to gate optional chains on non-empty strings.
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
