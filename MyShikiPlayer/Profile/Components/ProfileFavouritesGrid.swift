//
//  ProfileFavouritesGrid.swift
//  MyShikiPlayer
//
//  Favourites poster grid (2:3). 6 columns, first 12 entries + counter.
//

import SwiftUI

struct ProfileFavouritesGrid: View {
    @Environment(\.appTheme) private var theme
    let favourites: [UserFavouriteAnime]
    let onOpen: (Int) -> Void

    private let maxVisible = 12

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 6), alignment: .leading, spacing: 14) {
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
                posterArea(fav)
                Text(displayTitle(fav))
                    .font(.dsBody(12, weight: .semibold))
                    .foregroundStyle(theme.fg)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func posterArea(_ fav: UserFavouriteAnime) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.bg2)
            if let url = posterURL(raw: fav.image) {
                CachedRemoteImage(
                    url: url,
                    contentMode: .fill,
                    placeholder: { Color.clear },
                    failure: { placeholder }
                )
            } else {
                placeholder
            }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            theme.bg2
            Text("?")
                .font(.dsTitle(22, weight: .heavy))
                .foregroundStyle(theme.fg3)
        }
    }

    private func posterURL(raw: String?) -> URL? {
        guard let raw, !raw.isEmpty, !raw.contains("missing_") else { return nil }
        if raw.hasPrefix("http") { return URL(string: raw) }
        if raw.hasPrefix("/") { return ShikimoriURL.media(path: raw) }
        return URL(string: raw)
    }

    private func displayTitle(_ fav: UserFavouriteAnime) -> String {
        if let r = fav.russian, !r.isEmpty { return r }
        return fav.name ?? "—"
    }
}
