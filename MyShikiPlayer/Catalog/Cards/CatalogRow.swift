//
//  CatalogRow.swift
//  MyShikiPlayer
//
//  Variant C (rows): horizontal row with poster, title, season,
//  episode count and score. Equivalent of CatalogRow from screens-catalog.jsx.
//

import SwiftUI

struct CatalogRow: View {
    @Environment(\.appTheme) private var theme
    let item: AnimeListItem
    var onOpen: () -> Void = {}

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 16) {
                CatalogPoster(item: item, cornerRadius: 6, showsScoreBadge: false)
                    .frame(width: 60, height: 90)

                VStack(alignment: .leading, spacing: 4) {
                    Text(romaji)
                        .dsMonoLabel(size: 9, tracking: 1.2)
                        .foregroundStyle(theme.fg3)
                    Text(displayTitle)
                        .font(.dsBody(14, weight: .semibold))
                        .foregroundStyle(theme.fg)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(seasonText)
                    .font(.dsBody(12))
                    .foregroundStyle(theme.fg2)
                    .frame(width: 180, alignment: .leading)

                Text(episodesText)
                    .font(.dsMono(12))
                    .foregroundStyle(theme.fg2)
                    .frame(width: 80, alignment: .leading)

                scoreView
                    .frame(width: 90, alignment: .leading)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var displayTitle: String {
        if let russian = item.russian, !russian.isEmpty { return russian }
        return item.name
    }

    private var romaji: String { item.name }

    private var seasonText: String {
        guard let date = item.releasedOn ?? item.airedOn else { return "—" }
        return String(date.prefix(4))
    }

    private var episodesText: String {
        if let ep = item.episodes, ep > 0 { return "\(ep) эп" }
        if let aired = item.episodesAired, aired > 0 { return "\(aired) эп" }
        return "—"
    }

    @ViewBuilder
    private var scoreView: some View {
        if let raw = item.score, !raw.isEmpty, raw != "0.0", raw != "0", let value = Double(raw) {
            HStack(spacing: 4) {
                DSIcon(name: .star, size: 12, weight: .bold)
                    .foregroundStyle(color(for: value))
                Text(String(format: "%.2f", value))
                    .font(.dsMono(12, weight: .semibold))
                    .foregroundStyle(color(for: value))
            }
        } else {
            Text("—")
                .font(.dsMono(12))
                .foregroundStyle(theme.fg3)
        }
    }

    private func color(for value: Double) -> Color {
        if value >= 9 { return theme.accent }
        if value >= 8 { return theme.warn }
        if value >= 7 { return theme.good }
        return theme.fg2
    }
}
