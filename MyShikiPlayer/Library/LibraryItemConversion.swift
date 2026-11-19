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
            // Show the global Shikimori rating on poster cards, not the
            // user's personal score. `CatalogPoster` and `CatalogRow` already
            // strip "0.0"/"0" placeholders, so emitting them is safe.
            score: animeScore.map { String(format: "%.2f", $0) },
            status: animeStatus,
            episodes: nil,
            episodesAired: nil,
            airedOn: Int(year) != nil ? "\(year)-01-01" : nil,
            releasedOn: nil
        )
    }

    /// Same title with the user-rate side replaced — the anime fields
    /// (title, poster, episode counters) don't change when a rate does.
    func updating(
        rateId: Int,
        status: String,
        score: Int,
        episodesWatched: Int,
        updatedAt: Date
    ) -> Self {
        Self(
            id: rateId,
            shikimoriId: shikimoriId,
            title: title,
            kind: kind,
            year: year,
            status: status,
            score: score,
            episodesWatched: episodesWatched,
            posterURL: posterURL,
            updatedAt: updatedAt,
            animeStatus: animeStatus,
            animeSeason: animeSeason,
            animeScore: animeScore,
            animeEpisodes: animeEpisodes,
            animeEpisodesAired: animeEpisodesAired
        )
    }

    /// "watched / out so far" for the poster chip, flagged when episodes the
    /// user hasn't seen are already out. Nil when nothing is out yet.
    var progressBadge: PosterProgressBadge? {
        let aired = animeEpisodesAired ?? 0
        let total = animeEpisodes ?? 0
        // Shikimori often leaves episodesAired at 0 (or one short) once a
        // title has finished — then everything planned is out.
        let available = animeStatus == "released" ? max(aired, total) : aired
        guard available > 0 else { return nil }
        // Watching ahead of Shikimori's aired counter (it lags a few hours
        // behind the actual release) must not read as "7 / 6".
        let shown = max(available, episodesWatched)
        let isFollowing = status == MyListStatus.watching.rawValue
            || status == MyListStatus.rewatching.rawValue
        return PosterProgressBadge(
            text: "\(episodesWatched) / \(shown)",
            hasNew: isFollowing && episodesWatched < shown
        )
    }
}
