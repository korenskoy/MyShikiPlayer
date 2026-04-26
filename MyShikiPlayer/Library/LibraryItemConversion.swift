//
//  LibraryItemConversion.swift
//  MyShikiPlayer
//
//  Bridge between AnimeListViewModel.Item (library model) and AnimeListItem
//  (REST model that Catalog cards are built around).
//  Library-specific fields like episodesWatched / updatedAt are rendered as
//  separate captions in LibraryView, not through AnimeListItem.
//

import Foundation

extension AnimeListViewModel.Item {
    var asAnimeListItem: AnimeListItem {
        AnimeListItem(
            id: shikimoriId,
            name: title,
            russian: nil,
            image: AnimeImageURLs(
                original: posterURL?.absoluteString,
                preview: posterURL?.absoluteString,
                x96: nil,
                x48: nil
            ),
            url: nil,
            kind: kind.lowercased(),
            score: score > 0 ? "\(score)" : nil,
            status: animeStatus,
            episodes: nil,
            episodesAired: nil,
            airedOn: nil,
            releasedOn: nil
        )
    }
}
