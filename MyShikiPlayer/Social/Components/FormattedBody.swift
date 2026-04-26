//
//  FormattedBody.swift
//  MyShikiPlayer
//
//  Renders ShikimoriText.Segment[] as a vertical stack: plain text,
//  spoilers (clickable block with blur), quotes (light inset).
//  Inline links [anime=N], [manga=N], [url] are clickable:
//  [anime=N] opens Details (via onOpenAnimeId), the rest go to the
//  external browser.
//

import AppKit
import SwiftUI

struct FormattedBody: View {
    @Environment(\.appTheme) private var theme
    let segments: [ShikimoriText.Segment]
    let lineSpacing: CGFloat
    let font: Font
    /// Callback to open Details inside the app. If nil, `[anime=N]` opens
    /// on shikimori.io in the browser (like the other entities).
    let onOpenAnimeId: ((Int) -> Void)?

    init(
        segments: [ShikimoriText.Segment],
        font: Font = .dsBody(14),
        lineSpacing: CGFloat = 5,
        onOpenAnimeId: ((Int) -> Void)? = nil
    ) {
        self.segments = segments
        self.font = font
        self.lineSpacing = lineSpacing
        self.onOpenAnimeId = onOpenAnimeId
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                segmentView(segment)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            handleURL(url)
        })
    }

    @ViewBuilder
    private func segmentView(_ segment: ShikimoriText.Segment) -> some View {
        switch segment {
        case .plain(let raw):
            Text(attributed(from: raw, accent: theme.accent))
                .font(font)
                .foregroundStyle(theme.fg2)
                .lineSpacing(lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        case .spoiler(let raw):
            SpoilerBlock(raw: raw, font: font, lineSpacing: lineSpacing)
        case .quote(let raw):
            QuoteBlock(raw: raw, font: font, lineSpacing: lineSpacing)
        }
    }

    // MARK: - URL routing

    /// Custom scheme for Shikimori inline links: `myshiki://<kind>/<id>`.
    /// `kind=anime` is routed to `onOpenAnimeId`. Other kinds and any
    /// http(s) links go to the system browser. Foreign schemes are passed
    /// to systemAction (on macOS equivalent to NSWorkspace.open).
    private func handleURL(_ url: URL) -> OpenURLAction.Result {
        if url.scheme == FormattedBody.appScheme {
            let kind = url.host ?? ""
            let idString = url.lastPathComponent
            guard let id = Int(idString) else { return .discarded }
            if kind == "anime", let onOpenAnimeId {
                onOpenAnimeId(id)
                return .handled
            }
            if let webURL = FormattedBody.shikimoriWebURL(kind: kind, id: id) {
                NSWorkspace.shared.open(webURL)
                return .handled
            }
            return .discarded
        }
        return .systemAction
    }

    static let appScheme = "myshiki"

    static func shikimoriWebURL(kind: String, id: Int) -> URL? {
        // Shikimori web: /animes, /mangas, /ranobe, /characters, /people, /users.
        let path: String
        switch kind {
        case "anime":     path = "animes"
        case "manga":     path = "mangas"
        case "ranobe":    path = "ranobe"
        case "character": path = "characters"
        case "person":    path = "people"
        case "user":      path = "users"
        default: return nil
        }
        return ShikimoriURL.web(path: "\(path)/\(id)")
    }
}

// MARK: - AttributedString

private func attributed(from raw: String, accent: Color) -> AttributedString {
    let inlines = ShikimoriText.parseInlines(raw)
    if inlines.isEmpty {
        return AttributedString(raw)
    }
    var out = AttributedString()
    for inline in inlines {
        switch inline {
        case .text(let t):
            out += AttributedString(t)
        case .anime(let id, let name):
            out += linkAttr(name, scheme: FormattedBody.appScheme, kind: "anime", id: id, accent: accent)
        case .manga(let id, let name):
            out += linkAttr(name, scheme: FormattedBody.appScheme, kind: "manga", id: id, accent: accent)
        case .ranobe(let id, let name):
            out += linkAttr(name, scheme: FormattedBody.appScheme, kind: "ranobe", id: id, accent: accent)
        case .character(let id, let name):
            out += linkAttr(name, scheme: FormattedBody.appScheme, kind: "character", id: id, accent: accent)
        case .person(let id, let name):
            out += linkAttr(name, scheme: FormattedBody.appScheme, kind: "person", id: id, accent: accent)
        case .user(let id, let name):
            out += linkAttr(name, scheme: FormattedBody.appScheme, kind: "user", id: id, accent: accent)
        case .external(let url, let label):
            var part = AttributedString(label)
            part.link = url
            part.foregroundColor = accent
            part.underlineStyle = .single
            out += part
        }
    }
    return out
}

private func linkAttr(_ label: String, scheme: String, kind: String, id: Int, accent: Color) -> AttributedString {
    var part = AttributedString(label)
    part.link = URL(string: "\(scheme)://\(kind)/\(id)")
    part.foregroundColor = accent
    part.underlineStyle = .single
    return part
}

// MARK: - Spoiler / quote

/// Spoiler block: blurred by default + label. Click to reveal.
private struct SpoilerBlock: View {
    @Environment(\.appTheme) private var theme
    let raw: String
    let font: Font
    let lineSpacing: CGFloat
    @State private var revealed: Bool = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { revealed.toggle() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("⚠ СПОЙЛЕР")
                        .font(.dsMono(10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(theme.warn)
                    Text(revealed ? "скрыть" : "показать")
                        .font(.dsMono(10))
                        .foregroundStyle(theme.fg3)
                }
                Text(attributed(from: raw, accent: theme.accent))
                    .font(font)
                    .foregroundStyle(revealed ? theme.fg2 : theme.fg3)
                    .lineSpacing(lineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .blur(radius: revealed ? 0 : 5)
                    .opacity(revealed ? 1 : 0.7)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.warn.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.warn.opacity(0.25), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Quote: accent border on the left + dimmed text.
private struct QuoteBlock: View {
    @Environment(\.appTheme) private var theme
    let raw: String
    let font: Font
    let lineSpacing: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(theme.accent.opacity(0.45))
                .frame(width: 3)
            Text(attributed(from: raw, accent: theme.accent))
                .font(font)
                .foregroundStyle(theme.fg3)
                .lineSpacing(lineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding(.leading, 12)
                .padding(.vertical, 2)
        }
    }
}
