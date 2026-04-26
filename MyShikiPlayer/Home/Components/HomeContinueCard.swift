//
//  HomeContinueCard.swift
//  MyShikiPlayer
//
//  "Continue watching" card: 16:9 poster, episode badge + play circle
//  over a dim overlay, title + note + progress bar.
//

import SwiftUI

struct HomeContinueCard: View {
    @Environment(\.appTheme) private var theme
    let item: HomeContinueItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                posterArea
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayTitle)
                        .font(.dsBody(13, weight: .semibold))
                        .foregroundStyle(theme.fg)
                        .lineLimit(1)
                    Text(footerMeta)
                        .font(.dsMono(10))
                        .foregroundStyle(theme.fg3)
                        .lineLimit(1)
                    DSProgressBar(value: item.progress, height: 3)
                        .padding(.top, 2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.card)
            }
            // Single clip — so the poster on top is clipped with the same radius
            // as the border below. Without this the image leaks past the stroke.
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var posterArea: some View {
        ZStack {
            CatalogPoster(item: item.anime, cornerRadius: 0, showsScoreBadge: false)
            LinearGradient(
                colors: [Color.black.opacity(0.6), Color.black.opacity(0)],
                startPoint: .bottom,
                endPoint: .top
            )
            Circle()
                .fill(theme.accent)
                .frame(width: 42, height: 42)
            DSIcon(name: .play, size: 16, weight: .bold)
                .foregroundStyle(theme.mode == .dark ? Color(hex: 0x0B0A0D) : Color.white)
                .offset(x: 1)

            VStack {
                HStack {
                    Text("ЭП. \(item.episodesWatched + 1)")
                        .font(.dsMono(10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.black.opacity(0.55))
                        )
                    Spacer()
                }
                Spacer()
            }
            .padding(10)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipped()
    }

    private var displayTitle: String {
        if let r = item.anime.russian, !r.isEmpty { return r }
        return item.anime.name
    }

    private var footerMeta: String {
        var parts: [String] = [item.note]
        if let denominator = item.effectiveDenominator, denominator > 0 {
            parts.append("\(item.episodesWatched)/\(denominator) эп")
        }
        return parts.joined(separator: " · ")
    }
}
