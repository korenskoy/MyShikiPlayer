//
//  CatalogCard.swift
//  MyShikiPlayer
//
//  Variant A (grid 5x): large poster card with the title below the poster.
//  Equivalent of CatalogCard from screens-catalog.jsx.
//

import SwiftUI

struct CatalogCard: View {
    @Environment(\.appTheme) private var theme
    let item: AnimeListItem
    var onOpen: () -> Void = {}

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                CatalogPoster(item: item)
                    .aspectRatio(2.0/3.0, contentMode: .fit)

                Text(displayTitle)
                    .font(.dsBody(13, weight: .semibold))
                    .foregroundStyle(theme.fg)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let romaji {
                    Text(romaji)
                        .font(.dsMono(10, weight: .medium))
                        .foregroundStyle(theme.fg3)
                        .lineLimit(1)
                }

                Text(metaText)
                    .font(.dsBody(11))
                    .foregroundStyle(theme.fg3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var displayTitle: String {
        if let russian = item.russian, !russian.isEmpty { return russian }
        return item.name
    }

    // Hide the romanized line when it duplicates the title (e.g. Library items
    // carry no separate russian/romaji, so both would render item.name).
    private var romaji: String? {
        item.name.caseInsensitiveCompare(displayTitle) == .orderedSame ? nil : item.name
    }

    private var metaText: String {
        var parts: [String] = []
        if let year { parts.append(year) }
        if let kind = item.kind?.uppercased(), !kind.isEmpty { parts.append(kind) }
        if let ep = item.episodes, ep > 0 { parts.append("\(ep) эп") }
        if let status = item.statusShortLabel { parts.append(status) }
        return parts.joined(separator: " · ")
    }

    private var year: String? {
        (item.releasedOn ?? item.airedOn).flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
    }
}
