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

    /// A segment of a formatted body: plain text, spoiler or quote.
    /// Content is raw BBCode (without the spoiler/quote wrapper), which is
    /// later parsed into `[Inline]` via `parseInlines`. HTML bodies are
    /// reduced to plain before this stage — there `[Inline]` will be a single `.text`.
    enum Segment: Equatable {
        case plain(String)
        case spoiler(String)
        case quote(String)
    }

    /// Inline fragment of a plain segment: either text, or a link to a
    /// Shikimori entity ([anime=N], [manga=N], …), or an external URL ([url]…[/url]).
    enum Inline: Equatable {
        case text(String)
        case anime(id: Int, name: String)
        case manga(id: Int, name: String)
        case ranobe(id: Int, name: String)
        case character(id: Int, name: String)
        case person(id: Int, name: String)
        case user(id: Int, name: String)
        case external(url: URL, label: String)
    }

    /// Parses a raw body (BBCode-first) into segments, separating [spoiler]
    /// and [quote] blocks. Segment content is raw BBCode (without the wrapper).
    /// HTML bodies (html_body) are converted to plain in advance: a single
    /// `.plain` segment without BBCode markup.
    static func segments(_ input: String?) -> [Segment] {
        guard let raw = input, !raw.isEmpty else { return [] }
        if raw.contains("<") && raw.contains(">") {
            let plain = stripHTML(raw)
            return plain.isEmpty ? [] : [.plain(plain)]
        }
        return parseBBCodeSegments(raw)
    }

    /// Parses a plain segment into an array of inline fragments: text + links.
    /// Returns `[.text(content)]` if there are no links (raw is already plain).
    static func parseInlines(_ raw: String) -> [Inline] {
        guard !raw.isEmpty else { return [] }
        let ns = raw as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        var matches: [(NSRange, Inline)] = []

        // 1. Shikimori entities: [anime=N]Name[/anime], etc.
        if let regex = try? NSRegularExpression(
            pattern: #"\[(anime|manga|ranobe|character|person|user)=(\d+)\]([\s\S]*?)\[/\1\]"#,
            options: [.caseInsensitive]
        ) {
            regex.enumerateMatches(in: raw, options: [], range: fullRange) { m, _, _ in
                guard let m else { return }
                let kind = ns.substring(with: m.range(at: 1)).lowercased()
                guard let id = Int(ns.substring(with: m.range(at: 2))) else { return }
                let nameRaw = ns.substring(with: m.range(at: 3))
                let name = stripBBCode(nameRaw)
                let label = name.isEmpty ? "ссылка" : name
                let inline: Inline?
                switch kind {
                case "anime":     inline = .anime(id: id, name: label)
                case "manga":     inline = .manga(id: id, name: label)
                case "ranobe":    inline = .ranobe(id: id, name: label)
                case "character": inline = .character(id: id, name: label)
                case "person":    inline = .person(id: id, name: label)
                case "user":      inline = .user(id: id, name: label)
                default:          inline = nil
                }
                if let inline { matches.append((m.range, inline)) }
            }
        }

        // 2. [url=…]label[/url]
        if let regex = try? NSRegularExpression(
            pattern: #"\[url=([^\]]+)\]([\s\S]*?)\[/url\]"#,
            options: [.caseInsensitive]
        ) {
            regex.enumerateMatches(in: raw, options: [], range: fullRange) { m, _, _ in
                guard let m, let url = URL(string: ns.substring(with: m.range(at: 1))) else { return }
                let labelRaw = ns.substring(with: m.range(at: 2))
                let label = stripBBCode(labelRaw)
                matches.append((m.range, .external(url: url, label: label.isEmpty ? url.absoluteString : label)))
            }
        }

        // 3. [url]https://…[/url] (without attribute)
        if let regex = try? NSRegularExpression(
            pattern: #"\[url\]([\s\S]*?)\[/url\]"#,
            options: [.caseInsensitive]
        ) {
            regex.enumerateMatches(in: raw, options: [], range: fullRange) { m, _, _ in
                guard let m else { return }
                let urlString = ns.substring(with: m.range(at: 1))
                guard let url = URL(string: urlString) else { return }
                matches.append((m.range, .external(url: url, label: urlString)))
            }
        }

        // Sort + drop overlapping ones (inner tags that ended up as the
        // label of an outer link).
        matches.sort { $0.0.location < $1.0.location }
        var filtered: [(NSRange, Inline)] = []
        var lastEnd = 0
        for entry in matches {
            if entry.0.location < lastEnd { continue }
            filtered.append(entry)
            lastEnd = entry.0.location + entry.0.length
        }

        var result: [Inline] = []
        var cursor = 0
        for (range, inline) in filtered {
            if range.location > cursor {
                let before = ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
                // stripBBCodeMarkers (no trim) — whitespace/newlines around
                // links are significant, otherwise text sticks to the label.
                let cleaned = stripBBCodeMarkers(before)
                if !cleaned.isEmpty { result.append(.text(cleaned)) }
            }
            result.append(inline)
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            let tail = ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
            let cleaned = stripBBCodeMarkers(tail)
            if !cleaned.isEmpty { result.append(.text(cleaned)) }
        }
        return result
    }

    private static func parseBBCodeSegments(_ input: String) -> [Segment] {
        // Look for top-level [spoiler]…[/spoiler] and [quote]…[/quote].
        // Segment content is kept raw — the inline parser will later split it
        // into text + links. Content between blocks is also raw.
        let pattern = #"\[(spoiler|quote)(?:=[^\]]*)?\]([\s\S]*?)\[/\1\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [.plain(input)]
        }
        let ns = input as NSString
        var segments: [Segment] = []
        var cursor = 0
        let fullRange = NSRange(location: 0, length: ns.length)
        regex.enumerateMatches(in: input, options: [], range: fullRange) { match, _, _ in
            guard let match else { return }
            let outer = match.range
            if outer.location > cursor {
                let before = ns.substring(with: NSRange(location: cursor, length: outer.location - cursor))
                if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.plain(before))
                }
            }
            let kind = ns.substring(with: match.range(at: 1)).lowercased()
            let content = ns.substring(with: match.range(at: 2))
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                switch kind {
                case "spoiler": segments.append(.spoiler(content))
                case "quote":   segments.append(.quote(content))
                default:        segments.append(.plain(content))
                }
            }
            cursor = outer.location + outer.length
        }
        if cursor < ns.length {
            let tail = ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
            if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.plain(tail))
            }
        }
        return segments
    }
}
