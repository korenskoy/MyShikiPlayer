//
//  HomePosterCard.swift
//  MyShikiPlayer
//
//  Generic poster card for the "Trending today" and "New episodes" sections.
//  Optional rank badge in the top-left corner (#01, #02, ...).
//

import SwiftUI

struct HomePosterCard: View {
    @Environment(\.appTheme) private var theme
    let item: AnimeListItem
    let rank: Int?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    CatalogPoster(item: item)
                        .aspectRatio(2.0/3.0, contentMode: .fit)

                    if let rank {
                        Text("#\(String(format: "%02d", rank))")
                            .font(.dsTitle(13, weight: .heavy))
                            .foregroundStyle(theme.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(theme.bg)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(theme.accent, lineWidth: 1.5)
                            )
                            .padding(8)
                    }
                }

                Text(title)
                    .font(.dsBody(13, weight: .semibold))
                    .foregroundStyle(theme.fg)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(metaText)
                    .font(.dsMono(10))
                    .foregroundStyle(theme.fg3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        if let ep = item.episodes, ep > 0 {
            parts.append("\(ep) эп")
        }
        return parts.joined(separator: " · ")
    }
}
