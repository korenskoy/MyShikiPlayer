//
//  FormattedFlow.swift
//  MyShikiPlayer
//
//  View-level rendering for `[ShikimoriText.Inline]`. Replaces the previous
//  `Text + Text(Image)` concatenation: that approach could not animate GIF
//  smileys (Image takes a single frame) nor explicitly size them. Here each
//  inline becomes its own View — text words flow through `InlineFlowLayout`,
//  smileys live in a dedicated `AnimatedSmileyView` (NSImageView under the
//  hood, animates GIFs natively).
//

import AppKit
import SwiftUI

/// Inline-flow rendering of a `[Inline]` list. Text is split into whitespace-
/// delimited tokens so the layout can wrap mid-paragraph; smileys become a
/// fixed-size `AnimatedSmileyView`. Click handling for links is preserved
/// via the per-token `AttributedString.link`.
struct InlineFlow: View {
    @Environment(\.formattedBodyContext) private var ctx
    let inlines: [ShikimoriText.Inline]
    let accent: Color
    let baseColor: Color
    /// Fixed pixel size of a smiley. Shikimori web uses 32×32; we run a bit
    /// smaller so they don't overpower 13–14pt body text but stay readable.
    let smileySize: CGFloat

    init(
        inlines: [ShikimoriText.Inline],
        accent: Color,
        baseColor: Color,
        smileySize: CGFloat = 22
    ) {
        self.inlines = inlines
        self.accent = accent
        self.baseColor = baseColor
        self.smileySize = smileySize
    }

    var body: some View {
        InlineFlowLayout(hSpacing: 0, lineSpacing: 2) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                switch run {
                case .word(let attr):
                    Text(attr).fixedSize()
                case .smiley(let token):
                    AnimatedSmileyView(token: token, size: smileySize)
                case .lineBreak:
                    // Zero-width sentinel — `InlineFlowLayout` treats width-0 subviews
                    // as forced wraps and uses the height for line spacing.
                    Color.clear.frame(width: 0, height: max(smileySize, 14))
                }
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            handleURL(url)
        })
    }

    private var runs: [InlineFlowRun] {
        inlines.flatMap(convert)
    }

    private func convert(_ inline: ShikimoriText.Inline) -> [InlineFlowRun] {
        switch inline {
        case .text(let raw):
            return tokenize(AttributedString(raw))
        case .smiley(let token):
            return [.smiley(token: token)]
        case .anime(let id, let name):
            return entityRun(kind: "anime", id: id, fallback: name)
        case .manga(let id, let name):
            return entityRun(kind: "manga", id: id, fallback: name)
        case .ranobe(let id, let name):
            return entityRun(kind: "ranobe", id: id, fallback: name)
        case .character(let id, let name):
            return entityRun(kind: "character", id: id, fallback: name)
        case .person(let id, let name):
            return entityRun(kind: "person", id: id, fallback: name)
        case .user(let id, let name):
            return entityRun(kind: "user", id: id, fallback: name)
        case .external(let url, let label):
            var part = AttributedString(label)
            part.link = url
            part.foregroundColor = accent
            part.underlineStyle = .single
            return tokenize(part)
        case .commentReference(let cid, let aid):
            return tokenize(InlineFlowAttr.commentRef(commentId: cid, authorId: aid, accent: accent, resolvers: ctx.resolvers))
        case .replies(let ids):
            return tokenize(InlineFlowAttr.replies(ids: ids, accent: accent, resolvers: ctx.resolvers))
        case .styled(let text, let style):
            return tokenize(InlineFlowAttr.styled(text: text, style: style))
        case .inlineCode(let code):
            var part = AttributedString(code)
            part.font = .system(size: 12, design: .monospaced)
            part.foregroundColor = .red
            return tokenize(part)
        }
    }

    /// Entity link runs straight through the renderer — Shikimori already
    /// supplies the resolved Russian title via the `<a data-attrs="…">` JSON
    /// payload, so we don't need a separate resolver hook.
    private func entityRun(kind: String, id: Int, fallback: String) -> [InlineFlowRun] {
        tokenize(InlineFlowAttr.entityLink(fallback, kind: kind, id: id, accent: accent))
    }

    private func handleURL(_ url: URL) -> OpenURLAction.Result {
        if url.scheme == FormattedBody.appScheme {
            let kind = url.host ?? ""
            let idString = url.lastPathComponent
            guard let id = Int(idString) else { return .discarded }
            if kind == "anime", let onOpenAnimeId = ctx.onOpenAnimeId {
                onOpenAnimeId(id)
                return .handled
            }
            if kind == "comment", let onOpenCommentId = ctx.onOpenCommentId {
                onOpenCommentId(id)
                return .handled
            }
            if let webURL = FormattedBody.shikimoriWebURL(kind: kind, id: id) {
                NSWorkspace.shared.open(webURL)
                return .handled
            }
            return .discarded
        }
        guard ShikimoriText.isSafeExternalURL(url) else { return .discarded }
        return .systemAction
    }
}

/// Atomic flow run: either a styled text token (one word, one whitespace, or
/// one newline) or a smiley image. Tokens are kept narrow enough that the
/// `InlineFlowLayout` can wrap on every gap without splitting words mid-character.
enum InlineFlowRun {
    case word(AttributedString)
    case smiley(token: String)
    case lineBreak
}

/// Splits an `AttributedString` into tokens preserving per-character
/// attributes. Whitespace runs collapse to a single " " token; newlines
/// become explicit `\n` tokens that the layout treats as a hard break.
func tokenize(_ attr: AttributedString) -> [InlineFlowRun] {
    let chars = String(attr.characters)
    guard !chars.isEmpty else { return [] }
    var out: [InlineFlowRun] = []
    var idx = chars.startIndex
    var anchor = idx
    while idx < chars.endIndex {
        let ch = chars[idx]
        if ch == "\n" {
            if anchor < idx { out.append(.word(slice(attr, from: anchor, to: idx, in: chars))) }
            out.append(.lineBreak)
            idx = chars.index(after: idx)
            anchor = idx
        } else if ch.isWhitespace {
            if anchor < idx { out.append(.word(slice(attr, from: anchor, to: idx, in: chars))) }
            // Coalesce consecutive (non-newline) whitespace into a single space.
            var end = idx
            while end < chars.endIndex, chars[end].isWhitespace, chars[end] != "\n" {
                end = chars.index(after: end)
            }
            out.append(.word(slice(attr, from: idx, to: chars.index(after: idx), in: chars)))
            idx = end
            anchor = idx
        } else {
            idx = chars.index(after: idx)
        }
    }
    if anchor < idx { out.append(.word(slice(attr, from: anchor, to: idx, in: chars))) }
    return out
}

private func slice(
    _ attr: AttributedString,
    from lower: String.Index,
    to upper: String.Index,
    in chars: String
) -> AttributedString {
    let lowerOffset = chars.distance(from: chars.startIndex, to: lower)
    let upperOffset = chars.distance(from: chars.startIndex, to: upper)
    let aLower = attr.index(attr.startIndex, offsetByCharacters: lowerOffset)
    let aUpper = attr.index(attr.startIndex, offsetByCharacters: upperOffset)
    return AttributedString(attr[aLower..<aUpper])
}

// MARK: - Attribute builders

/// Static helpers for producing styled `AttributedString` runs that the
/// flow renderer feeds into `tokenize`.
enum InlineFlowAttr {
    static func entityLink(_ label: String, kind: String, id: Int, accent: Color) -> AttributedString {
        var part = AttributedString(label)
        part.link = URL(string: "\(FormattedBody.appScheme)://\(kind)/\(id)")
        part.foregroundColor = accent
        part.underlineStyle = .single
        return part
    }

    /// `[comment=CID;AID]` — clickable to the same comment if it's on the
    /// page (scrolls), to the user page otherwise.
    static func commentRef(commentId: Int, authorId: Int?, accent: Color, resolvers: CommentResolvers) -> AttributedString {
        let onPage = resolvers.nickByCommentId(commentId)
        let nick: String?
        if let onPage {
            nick = onPage
        } else if let aid = authorId, let resolved = resolvers.nickByAuthorId(aid) {
            nick = resolved
        } else {
            nick = nil
        }
        let label = nick.map { "@\($0)" } ?? "→к комменту"
        var part = AttributedString(label)
        part.foregroundColor = accent
        part.underlineStyle = .single
        if onPage != nil {
            part.link = URL(string: "\(FormattedBody.appScheme)://comment/\(commentId)")
        } else if let aid = authorId {
            part.link = URL(string: "\(FormattedBody.appScheme)://user/\(aid)")
        }
        return part
    }

    /// `[replies=…]` rendered on its own line as "↩ Ответы: @x, @y".
    static func replies(ids: [Int], accent: Color, resolvers: CommentResolvers) -> AttributedString {
        let labels = ids.map { id -> String in
            if let nick = resolvers.nickByCommentId(id) { return "@\(nick)" }
            return "#\(id)"
        }
        var part = AttributedString("\n↩ Ответы: " + labels.joined(separator: ", "))
        part.foregroundColor = accent.opacity(0.75)
        return part
    }

    static func styled(text: String, style: ShikimoriText.InlineStyle) -> AttributedString {
        var part = AttributedString(text)
        var intent: InlinePresentationIntent = []
        if style.bold   { intent.insert(.stronglyEmphasized) }
        if style.italic { intent.insert(.emphasized) }
        if !intent.isEmpty { part.inlinePresentationIntent = intent }
        if style.underline { part.underlineStyle = .single }
        if style.strikethrough { part.strikethroughStyle = .single }
        if let hex = style.colorHex, let color = colorFromHex(hex) {
            part.foregroundColor = color
        }
        return part
    }

    private static func colorFromHex(_ hex: String) -> Color? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let rgb = UInt32(s, radix: 16) else { return nil }
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Animated smiley

/// Bundle GIF rendered through `NSImageView` so multi-frame animation runs
/// natively. Constrained to `size × size` so it doesn't inflate line height
/// — Shikimori shows smileys at 32px; we run a bit smaller so they sit
/// closer to surrounding 13pt text without disappearing.
struct AnimatedSmileyView: NSViewRepresentable {
    let token: String
    let size: CGFloat

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageFrameStyle = .none
        view.imageScaling = .scaleProportionallyDown
        view.animates = true
        view.image = SmileyCatalog.image(for: token)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: size),
            view.heightAnchor.constraint(equalToConstant: size),
        ])
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if nsView.image == nil {
            nsView.image = SmileyCatalog.image(for: token)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }
}

// MARK: - InlineFlowLayout

/// Inline flow layout — places subviews horizontally, wrapping to a new line
/// when the next subview would overflow. A subview whose width is `0` is
/// skipped (used by `\n`-tokens to force a hard break).
struct InlineFlowLayout: Layout {
    var hSpacing: CGFloat = 0
    var lineSpacing: CGFloat = 2

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return computeLayout(in: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(in: bounds.width, subviews: subviews)
        for (idx, frame) in result.frames.enumerated() {
            let origin = CGPoint(x: bounds.minX + frame.origin.x, y: bounds.minY + frame.origin.y)
            subviews[idx].place(at: origin, proposal: ProposedViewSize(frame.size))
        }
    }

    private func computeLayout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineH: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            // Hard line break sentinel — width-0 subviews force a wrap and
            // contribute their height to the row spacing.
            if size.width == 0 {
                lineH = max(lineH, size.height)
                y += lineH + lineSpacing
                x = 0
                lineH = 0
                frames.append(CGRect(origin: CGPoint(x: x, y: y), size: .zero))
                continue
            }
            if x + size.width > width, x > 0 {
                y += lineH + lineSpacing
                x = 0
                lineH = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + hSpacing
            lineH = max(lineH, size.height)
            maxX = max(maxX, x)
        }
        return (CGSize(width: maxX, height: y + lineH), frames)
    }
}
