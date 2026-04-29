//
//  FormattedBody.swift
//  MyShikiPlayer
//
//  Renders ShikimoriText.Segment[] as a vertical stack: plain text, spoilers
//  (clickable block with blur), quotes (light inset), Markdown blocks, and
//  images. Inline runs (links, smileys, styled text) are flowed by
//  `InlineFlow` (see `FormattedFlow.swift`). The flow uses `Text` for prose
//  and `AnimatedSmileyView` (NSImageView) for animated GIF smileys.
//

import AppKit
import SwiftUI

/// Resolvers for forum-only references inside a comment body. With the
/// HTML parser most things (entity names, image URLs) come pre-resolved
/// from Shikimori — only the comment-author lookups stay, because they're
/// scoped to "the current page of comments".
struct CommentResolvers {
    /// Maps an author id (the `userId` slot of `<a class="b-mention">`) to
    /// the nickname displayed on a comment in the same topic.
    var nickByAuthorId: (Int) -> String? = { _ in nil }
    /// Maps a comment id (the `id` slot of `<a class="b-mention">`) to the
    /// nickname of that comment's author.
    var nickByCommentId: (Int) -> String? = { _ in nil }

    static let empty = CommentResolvers()
}

/// Shared rendering hooks for a `FormattedBody` subtree — passed through
/// the environment so nested blocks (`SpoilerBlock`/`QuoteBlock`/…) and
/// the inline runs (`InlineFlow`) don't re-thread the same three params
/// through every layer.
struct FormattedBodyContext {
    var onOpenAnimeId: ((Int) -> Void)? = nil
    var onOpenCommentId: ((Int) -> Void)? = nil
    var resolvers: CommentResolvers = .empty
}

private struct FormattedBodyContextKey: EnvironmentKey {
    static let defaultValue = FormattedBodyContext()
}

extension EnvironmentValues {
    var formattedBodyContext: FormattedBodyContext {
        get { self[FormattedBodyContextKey.self] }
        set { self[FormattedBodyContextKey.self] = newValue }
    }
}

struct FormattedBody: View {
    @Environment(\.appTheme) private var theme
    let segments: [ShikimoriText.Segment]
    let lineSpacing: CGFloat
    let segmentSpacing: CGFloat
    let font: Font
    /// When non-nil, this view installs a fresh `FormattedBodyContext` for
    /// itself + descendants. Recursive uses inside `SpoilerBlock`/`QuoteBlock`
    /// pass `nil` so the nested body inherits the parent's context.
    private let installedContext: FormattedBodyContext?

    /// Top-level callers (`TopicDetailView`, `LinearPostRow`, `DescriptionSection`).
    /// Sets the rendering context that every nested block / inline flow reads.
    init(
        segments: [ShikimoriText.Segment],
        font: Font = .dsBody(14),
        lineSpacing: CGFloat = 5,
        segmentSpacing: CGFloat = 10,
        onOpenAnimeId: ((Int) -> Void)? = nil,
        onOpenCommentId: ((Int) -> Void)? = nil,
        commentResolvers: CommentResolvers = .empty
    ) {
        self.segments = segments
        self.font = font
        self.lineSpacing = lineSpacing
        self.segmentSpacing = segmentSpacing
        self.installedContext = FormattedBodyContext(
            onOpenAnimeId: onOpenAnimeId,
            onOpenCommentId: onOpenCommentId,
            resolvers: commentResolvers
        )
    }

    /// Recursive use inside spoiler/quote blocks — the existing ambient
    /// `FormattedBodyContext` flows through unchanged. Quotes pass a smaller
    /// `segmentSpacing` (~4pt) so multi-line quotes render as a tight block
    /// instead of paragraph-sized gaps between lines, matching Shikimori's
    /// web layout.
    init(
        segments: [ShikimoriText.Segment],
        font: Font,
        lineSpacing: CGFloat,
        segmentSpacing: CGFloat = 10
    ) {
        self.segments = segments
        self.font = font
        self.lineSpacing = lineSpacing
        self.segmentSpacing = segmentSpacing
        self.installedContext = nil
    }

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: segmentSpacing) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                segmentView(segment)
            }
        }
        if let installedContext {
            stack.environment(\.formattedBodyContext, installedContext)
        } else {
            stack
        }
    }

    @ViewBuilder
    private func segmentView(_ segment: ShikimoriText.Segment) -> some View {
        switch segment {
        case .plain(let raw):
            inlineFlow(raw, baseColor: theme.fg2)
                .font(font)
                .foregroundStyle(theme.fg2)
        case .spoiler(let label, let raw):
            SpoilerBlock(label: label, raw: raw, font: font, lineSpacing: lineSpacing)
        case .quote(let raw, let author):
            QuoteBlock(raw: raw, author: author, font: font, lineSpacing: lineSpacing)
        case .heading(let level, let text):
            HeadingBlock(level: level, text: text)
        case .markdownQuote(let text):
            MarkdownQuoteBlock(text: text, font: font, lineSpacing: lineSpacing)
        case .codeBlock(let language, let text):
            CodeBlock(language: language, text: text)
        case .list(let items):
            BulletList(items: items, font: font, lineSpacing: lineSpacing)
        case .image(let url):
            ImageBlock(url: url)
        }
    }

    private func inlineFlow(_ raw: String, baseColor: Color) -> InlineFlow {
        InlineFlow(
            inlines: ShikimoriText.parseInlines(raw),
            accent: theme.accent,
            baseColor: baseColor
        )
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

// MARK: - Spoiler / quote

/// Spoiler block: when collapsed, only a tappable header bar is visible —
/// matches Shikimori's web client where the hidden body adds no vertical
/// space until revealed. The Shikimori spoiler title (e.g. "а если чут-чут
/// напряжет мускулы?") replaces the generic "СПОЙЛЕР" label when present.
private struct SpoilerBlock: View {
    @Environment(\.appTheme) private var theme
    let label: String?
    let raw: String
    let font: Font
    let lineSpacing: CGFloat
    @State private var revealed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { revealed.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if revealed {
                Rectangle()
                    .fill(theme.warn.opacity(0.18))
                    .frame(height: 1)
                // Recurse through the full block parser so `[image=ID]`,
                // `[quote]`, headings, and code blocks inside the spoiler
                // render as proper blocks. The ambient
                // `FormattedBodyContext` flows through unchanged via the
                // env propagation.
                FormattedBody(
                    segments: ShikimoriText.segments(raw),
                    font: font,
                    lineSpacing: lineSpacing
                )
                .foregroundStyle(theme.fg2)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.warn.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(theme.warn.opacity(0.25), lineWidth: 1)
        )
    }

    /// Header bar — clickable when collapsed and pinned at the top of the
    /// spoiler box when revealed. Background / border live on the outer
    /// VStack so the same rounded rectangle wraps both the header and the
    /// revealed content (visually grouping them as one spoiler).
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: revealed ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.warn)
            if let label, !label.isEmpty {
                Text(label)
                    .font(.dsBody(12, weight: .medium))
                    .foregroundStyle(theme.fg2)
                    .multilineTextAlignment(.leading)
            } else {
                Text("СПОЙЛЕР")
                    .font(.dsMono(10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(theme.warn)
            }
            Text(revealed ? "скрыть" : "показать")
                .font(.dsMono(10))
                .foregroundStyle(theme.fg3)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Quote: accent stripe on the left + author header (when present) + dimmed
/// text. Uses an `overlay(alignment: .leading)` for the stripe instead of an
/// HStack so the rectangle's greedy vertical sizing can't inflate the row
/// height beyond the author / body — that was causing a tall empty band
/// under one-line quotes in the flat thread.
private struct QuoteBlock: View {
    @Environment(\.appTheme) private var theme
    let raw: String
    let author: String?
    let font: Font
    let lineSpacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let author, !author.isEmpty {
                HStack(spacing: 4) {
                    Text("↻")
                        .font(.dsMono(10, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    Text(author)
                        .font(.dsBody(11, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            // Compact segment spacing inside quotes — Shikimori renders
            // multi-line quotes as a single tight block, not as standalone
            // paragraphs separated by 10pt gaps.
            FormattedBody(
                segments: ShikimoriText.segments(raw),
                font: font,
                lineSpacing: lineSpacing,
                segmentSpacing: 4
            )
            .foregroundStyle(theme.fg3)
        }
        .padding(.leading, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(theme.accent.opacity(0.45))
                .frame(width: 3)
        }
    }
}

// MARK: - Markdown blocks

/// Markdown heading: levels 1…5 map to descending font sizes/weights.
private struct HeadingBlock: View {
    @Environment(\.appTheme) private var theme
    let level: Int
    let text: String

    private var headingFont: Font {
        switch level {
        case 1: return .dsTitle(24, weight: .heavy)
        case 2: return .dsTitle(19, weight: .bold)
        case 3: return .dsTitle(16, weight: .semibold)
        case 4: return .dsBody(14, weight: .semibold)
        default: return .dsBody(13, weight: .semibold)
        }
    }

    var body: some View {
        InlineFlow(
            inlines: ShikimoriText.parseInlines(text),
            accent: theme.accent,
            baseColor: theme.fg
        )
        .font(headingFont)
        .foregroundStyle(theme.fg)
        .padding(.top, level <= 2 ? 6 : 2)
    }
}

/// Markdown `> quote` — light-grey inset, no author header (BBCode `[quote]`
/// covers the case with a known author separately).
private struct MarkdownQuoteBlock: View {
    @Environment(\.appTheme) private var theme
    let text: String
    let font: Font
    let lineSpacing: CGFloat

    var body: some View {
        InlineFlow(
            inlines: ShikimoriText.parseInlines(text),
            accent: theme.accent,
            baseColor: theme.fg3
        )
        .font(font)
        .foregroundStyle(theme.fg3)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.chipBg.opacity(0.6))
        )
    }
}

/// Fenced code block: monospaced text on a dark surface, optional language
/// label in the top-right corner.
private struct CodeBlock: View {
    @Environment(\.appTheme) private var theme
    let language: String?
    let text: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.fg)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.fg.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(theme.line, lineWidth: 1)
                )
            if let lang = language, !lang.isEmpty {
                Text(lang.uppercased())
                    .font(.dsMono(9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(theme.fg3)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(theme.bg)
                    )
                    .padding(8)
            }
        }
    }
}

/// `<img>` and `<a class="b-image">` from `html_body` both arrive here as
/// a resolved URL. We rely on `AsyncImage` to size by aspect (`scaledToFit`
/// with a soft cap of 360pt height) and degrade to a chip-link when the
/// image fails to load.
private struct ImageBlock: View {
    @Environment(\.appTheme) private var theme
    let url: URL

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                placeholder(text: "Загрузка изображения…")
            case .success(let image):
                // Left-align the rendered image: an HStack with a trailing
                // Spacer keeps the image at its natural fitted size while
                // the row consumes the remaining body width. Using
                // `.frame(maxWidth: .infinity, alignment: .leading)` on the
                // image itself would expand the *clipShape* rectangle to
                // full body width even when the picture is portrait.
                HStack(alignment: .top, spacing: 0) {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Spacer(minLength: 0)
                }
            case .failure:
                chip(label: "🖼  \(url.absoluteString)", url: url)
            @unknown default:
                placeholder(text: "Загрузка изображения…")
            }
        }
    }

    private func placeholder(text: String) -> some View {
        Text(text)
            .font(.dsBody(11))
            .foregroundStyle(theme.fg3)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(theme.chipBg.opacity(0.6))
            )
    }

    @ViewBuilder
    private func chip(label: String, url: URL?) -> some View {
        Button {
            // Mirror the parser's allowlist: only open http(s)/mailto. The
            // chip URL is partly built from user-supplied content (failure
            // path of `[img]URL[/img]`), so this is not just defence-in-depth.
            if let url, ShikimoriText.isSafeExternalURL(url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            Text(label)
                .font(.dsBody(11, weight: .medium))
                .foregroundStyle(theme.accent)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.chipBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(theme.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }
}

/// Markdown unordered list. Bullets are rendered as accent dots; each item
/// runs through the regular inline parser, so `[anime=…]` / smileys still
/// resolve inside list items.
private struct BulletList: View {
    @Environment(\.appTheme) private var theme
    let items: [String]
    let font: Font
    let lineSpacing: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .font(font)
                        .foregroundStyle(theme.accent)
                    InlineFlow(
                        inlines: ShikimoriText.parseInlines(item),
                        accent: theme.accent,
                        baseColor: theme.fg2
                    )
                    .font(font)
                    .foregroundStyle(theme.fg2)
                }
            }
        }
    }
}
