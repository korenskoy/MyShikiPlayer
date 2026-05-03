//
//  ProfileFavouritesGrid.swift
//  MyShikiPlayer
//
//  Favourites poster grid (2:3). 6 columns, first 12 entries.
//  Reuses CatalogPoster so missing posters fall back to the same striped
//  placeholder used elsewhere in the app instead of a "?" tile.
//

import SwiftUI

struct ProfileFavouritesGrid: View {
    @Environment(\.appTheme) private var theme
    let favourites: [UserFavouriteAnime]
    let onOpen: (Int) -> Void

    private let maxVisible = 12

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 6),
            alignment: .leading,
            spacing: 14
        ) {
            ForEach(favourites.prefix(maxVisible), id: \.id) { fav in
                card(fav)
            }
        }
    }

    private func card(_ fav: UserFavouriteAnime) -> some View {
        Button {
            onOpen(fav.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CatalogPoster(item: Self.toListItem(fav), showsScoreBadge: false)
                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                Text(displayTitle(fav))
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

    private func displayTitle(_ fav: UserFavouriteAnime) -> String {
        if let r = fav.russian, !r.isEmpty { return r }
        return fav.name ?? "—"
    }

    /// Lifts the lightweight favourites payload (id + names + single image
    /// string) into the richer `AnimeListItem` that `CatalogPoster` consumes.
    /// Missing fields stay nil; the poster filters `missing_*` strings on its
    /// own and falls back to the striped placeholder.
    private static func toListItem(_ fav: UserFavouriteAnime) -> AnimeListItem {
        AnimeListItem(
            id: fav.id,
            name: fav.name ?? "",
            russian: fav.russian,
            image: AnimeImageURLs(
                original: fav.image,
                preview: fav.image,
                x96: nil,
                x48: nil
            ),
            url: fav.url,
            kind: nil,
            score: nil,
            status: nil,
            episodes: nil,
            episodesAired: nil,
            airedOn: nil,
            releasedOn: nil
        )
    }
}
