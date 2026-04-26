//
//  CatalogPoster.swift
//  MyShikiPlayer
//
//  Anime poster for catalog cards. Loads the real image via CachedRemoteImage;
//  on missing URL or error falls back to a striped placeholder with a
//  hue-dependent fill (equivalent of Poster from primitives.jsx).
//

import SwiftUI

struct CatalogPoster: View {
    @Environment(\.appTheme) private var theme

    let item: AnimeListItem
    var cornerRadius: CGFloat = 10
    var showsScoreBadge: Bool = true

    var body: some View {
        ZStack {
            posterImage

            if showsScoreBadge, let scoreText {
                VStack {
                    HStack {
                        Spacer()
                        scoreBadge(scoreText)
                    }
                    Spacer()
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

    private func scoreBadge(_ text: String) -> some View {
        Text(text)
            .font(.dsMono(10, weight: .bold))
            .foregroundStyle(scoreColor(for: text))
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
