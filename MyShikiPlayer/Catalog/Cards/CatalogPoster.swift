//
//  CatalogPoster.swift
//  MyShikiPlayer
//
//  Anime poster for catalog cards. Loads the real image via CachedRemoteImage;
//  on missing URL or error falls back to a striped placeholder with a
//  hue-dependent fill (equivalent of Poster from primitives.jsx).
//

import SwiftUI

/// Watch progress shown on a poster: "3 / 5". `hasNew` marks a title the
/// user follows that already has unwatched episodes out.
struct PosterProgressBadge: Equatable {
    let text: String
    let hasNew: Bool
}

struct CatalogPoster: View {
    @Environment(\.appTheme) private var theme

    let item: AnimeListItem
    var cornerRadius: CGFloat = 10
    var showsScoreBadge: Bool = true
    /// Episode counter ("12 / 24") pinned to the top-right corner. When set,
    /// the score badge moves to the top-left so the two don't overlap.
    var episodesText: String?
    /// Corner dot with the user's list status, expanding into a pill on hover.
    var showsListStatus: Bool = false
    /// "watched / out" chip in the top-left corner (library screens).
    var progress: PosterProgressBadge?

    var body: some View {
        ZStack(alignment: .top) {
            posterImage

            if badgeScoreText != nil || episodesText != nil || progress != nil {
                HStack(alignment: .top, spacing: 6) {
                    if let progress {
                        badge(progress.text, color: progress.hasNew ? theme.accent : theme.fg)
                    } else if episodesText != nil, let score = badgeScoreText {
                        badge(score, color: scoreColor(for: score))
                    }
                    Spacer(minLength: 0)
                    if let episodesText {
                        badge(episodesText, color: theme.fg2)
                    } else if let score = badgeScoreText {
                        badge(score, color: scoreColor(for: score))
                    }
                }
                .padding(8)
                .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(theme.line, lineWidth: 0.5)
        )
        // After the clip on purpose: the expanded pill may be wider than a
        // small poster (list rows are 60pt) and must not be cut off.
        .overlay(alignment: .bottomLeading) {
            if showsListStatus {
                ListStatusBadge(animeId: item.id)
                    .padding(3)
            }
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let url = posterURL {
            CachedRemoteImage(
                url: url,
                contentMode: .fill,
                placeholder: { stripeFallback },
                failure: { stripeFallback }
            )
        } else {
            stripeFallback
        }
    }

    /// Striped fallback with a hue derived from the id.
    private var stripeFallback: some View {
        let hue = Double((item.id * 37) % 360) / 360.0
        let base = Color(hue: hue, saturation: 0.35, brightness: theme.mode == .dark ? 0.35 : 0.82)
        let stripe = Color(hue: hue, saturation: 0.55, brightness: theme.mode == .dark ? 0.45 : 0.90)
        return ZStack {
            base
            GeometryReader { geo in
                let step: CGFloat = 10
                let count = Int((geo.size.width + geo.size.height) / step) + 2
                Canvas { ctx, size in
                    ctx.rotate(by: .degrees(-30))
                    for i in 0..<count {
                        let x = CGFloat(i) * step - size.height
                        ctx.fill(
                            Path(CGRect(x: x, y: -size.height, width: 3, height: size.height * 3)),
                            with: .color(stripe)
                        )
                    }
                }
            }
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.dsMono(10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(theme.bg.opacity(0.9))
            )
    }

    private func scoreColor(for text: String) -> Color {
        guard let value = Double(text) else { return theme.fg2 }
        if value >= 9 { return theme.accent }
        if value >= 8 { return theme.warn }
        if value >= 7 { return theme.good }
        return theme.fg2
    }

    private var badgeScoreText: String? {
        showsScoreBadge ? scoreText : nil
    }

    private var scoreText: String? {
        guard let raw = item.score, !raw.isEmpty, raw != "0.0", raw != "0" else { return nil }
        return raw
    }

    private var posterURL: URL? {
        let candidates = [
            item.image?.preview,
            item.image?.original,
            item.image?.x96,
            item.image?.x48,
        ]
        for raw in candidates {
            // For anime without a poster Shikimori returns `/assets/globals/missing_*.jpg`.
            // It is not a real poster — loading it is pointless, so use the
            // striped fallback right away.
            guard let raw, !raw.isEmpty, !raw.contains("missing_") else { continue }
            if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
            if raw.hasPrefix("/") { return ShikimoriURL.media(path: raw) }
            return URL(string: raw)
        }
        return nil
    }
}
