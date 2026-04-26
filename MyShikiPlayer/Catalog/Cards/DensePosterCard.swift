//
//  DensePosterCard.swift
//  MyShikiPlayer
//
//  Variant B (dense 8x): compact card — poster + one-line title + year.
//  "Shikimori-like" style. Equivalent of DensePosterCard from screens-catalog.jsx.
//

import SwiftUI

struct DensePosterCard: View {
    @Environment(\.appTheme) private var theme
    let item: AnimeListItem
    var onOpen: () -> Void = {}

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 3) {
                CatalogPoster(item: item, cornerRadius: 6)
                    .aspectRatio(2.0/3.0, contentMode: .fit)

                Text(displayTitle)
                    .font(.dsBody(10, weight: .semibold))
                    .foregroundStyle(theme.fg)
                    .lineLimit(1)

                Text(yearText)
                    .font(.dsMono(9))
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

    private var yearText: String {
        (item.releasedOn ?? item.airedOn).flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil } ?? "—"
    }
}
