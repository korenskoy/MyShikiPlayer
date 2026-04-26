//
//  HomeRecoCards.swift
//  MyShikiPlayer
//
//  "For you" section — one large recommendation card + 4 small ones.
//  Data is currently sourced as top-ranked — a placeholder until a real
//  recommendation engine is in place.
//

import SwiftUI

struct HomeRecoFeature: View {
    @Environment(\.appTheme) private var theme
    let item: AnimeListItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                CatalogPoster(item: item, cornerRadius: 16, showsScoreBadge: false)
                    .frame(minHeight: 280)

                LinearGradient(
                    stops: [
                        .init(color: theme.bg.opacity(0.95), location: 0),
                        .init(color: theme.bg.opacity(0.2), location: 0.7),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("ДЛЯ ВАС")
                        .font(.dsLabel(10))
                        .tracking(1.5)
                        .foregroundStyle(theme.accent)
                    Text(title)
                        .font(.dsTitle(26, weight: .bold))
                        .foregroundStyle(theme.fg)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !metaText.isEmpty {
                        Text(metaText)
                            .font(.dsBody(12))
                            .foregroundStyle(theme.fg2)
                            .lineLimit(1)
                    }
                }
                .padding(22)
                .frame(maxWidth: 360, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var title: String {
        if let r = item.russian, !r.isEmpty { return r }
        return item.name
    }

    private var metaText: String {
        var parts: [String] = []
        if let year = (item.releasedOn ?? item.airedOn).flatMap({ $0.count >= 4 ? String($0.prefix(4)) : nil }) {
            parts.append(year)
        }
        if let kind = item.kind?.uppercased(), !kind.isEmpty { parts.append(kind) }
        if let score = item.score, !score.isEmpty, score != "0.0", score != "0" {
            parts.append("★ \(score)")
        }
        return parts.joined(separator: " · ")
    }
}

struct HomeRecoSmall: View {
    @Environment(\.appTheme) private var theme
    let item: AnimeListItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                CatalogPoster(item: item, cornerRadius: 6, showsScoreBadge: false)
                    .frame(width: 70, height: 105)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.dsMono(9))
                        .tracking(1)
                        .foregroundStyle(theme.fg3)
                        .lineLimit(1)
                    Text(title)
                        .font(.dsBody(13, weight: .semibold))
                        .foregroundStyle(theme.fg)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    scoreView
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        if let r = item.russian, !r.isEmpty { return r }
        return item.name
    }

    @ViewBuilder
    private var scoreView: some View {
        if let raw = item.score, !raw.isEmpty, raw != "0.0", raw != "0", let value = Double(raw) {
            HStack(spacing: 4) {
                DSIcon(name: .star, size: 11, weight: .bold)
                Text(String(format: "%.2f", value))
                    .font(.dsMono(11, weight: .semibold))
            }
            .foregroundStyle(scoreColor(value))
        }
    }

    private func scoreColor(_ value: Double) -> Color {
        if value >= 9 { return theme.accent }
        if value >= 8 { return theme.warn }
        if value >= 7 { return theme.good }
        return theme.fg2
    }
}
