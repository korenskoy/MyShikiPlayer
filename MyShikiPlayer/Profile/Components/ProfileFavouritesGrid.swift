//
//  ProfileFavouritesGrid.swift
//  MyShikiPlayer
//
//  Favourites poster grid (2:3). 6 columns, first 12 entries.
//  Renders cards through `CatalogPoster` — the same component used by the
//  catalog tab, so the striped placeholder, hue fallback, and image
//  pipeline are identical.
//

import SwiftUI

struct ProfileFavouritesGrid: View {
    @Environment(\.appTheme) private var theme
    let favourites: [AnimeListItem]
    let onOpen: (Int) -> Void

    private let maxVisible = 12

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 6),
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(favourites.prefix(maxVisible), id: \.id) { item in
                card(item)
            }
        }
    }

    private func card(_ item: AnimeListItem) -> some View {
        Button {
            onOpen(item.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CatalogPoster(item: item, showsScoreBadge: false)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                Text(displayTitle(item))
                    .font(.dsBody(13, weight: .semibold))
                    .foregroundStyle(theme.fg)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func displayTitle(_ item: AnimeListItem) -> String {
        if let r = item.russian, !r.isEmpty { return r }
        return item.name
    }
}
