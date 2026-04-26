//
//  EpisodesLoader.swift
//  MyShikiPlayer
//
//  Pure helpers for the Episodes UI inside the Details screen:
//  episode count derivation, "available in Kodik" markup, and the
//  per-episode preview dictionary built from `/api/animes/{id}/videos`.
//
//  Stateless — input data comes from the snapshot already loaded by
//  `AnimeDetailsRepository`. Lives next to AnimeDetailsViewModel.
//

import Foundation

@MainActor
enum EpisodesLoader {
    /// Best-guess number of episodes for the picker. Order:
    ///   1. Max key in the chosen Kodik translation (most accurate).
    ///   2. Detail's `episodeCountForPickerFallback` (Shikimori meta).
    ///   3. `userEpisodesWatched + 4` so the user can mark a few more
    ///      ahead of what we know.
    static func episodeCount(
        catalogEntries: [KodikCatalogEntry],
        selectedTranslationId: Int?,
        detail: AnimeDetail?,
        userEpisodesWatched: Int
    ) -> Int {
        if let tid = selectedTranslationId,
           let entry = catalogEntries.first(where: { $0.translation.id == tid }),
           let maxKey = entry.episodes.keys.max(), maxKey >= 1 {
            return maxKey
        }
        if let cap = detail?.episodeCountForPickerFallback, cap >= 1 { return cap }
        return max(12, userEpisodesWatched + 4)
    }

    /// Episodes confirmed available in Kodik (used by EpisodeGrid markup).
    static func episodesWithSources(
        catalogEntries: [KodikCatalogEntry],
        selectedTranslationId: Int?
    ) -> Set<Int> {
        guard let tid = selectedTranslationId,
              let entry = catalogEntries.first(where: { $0.translation.id == tid }) else {
            return []
        }
        return Set(entry.episodes.keys)
    }

    /// Distinct studios in the catalog — used for the "X studios" badge.
    static func uniqueStudiosCount(catalogEntries: [KodikCatalogEntry]) -> Int {
        Set(catalogEntries.map(\.translation.id)).count
    }

    /// Episode previews from `/api/animes/{id}/videos`, filtered by
    /// `kind == "episode_preview"`. Key is episode number (from `name`,
    /// usually a zero-padded string like "07").
    static func episodePreviews(from videos: [AnimeVideoREST]) -> [Int: URL] {
        var result: [Int: URL] = [:]
        for video in videos where video.kind?.lowercased() == "episode_preview" {
            guard let name = video.name,
                  let episode = Int(name),
                  let raw = video.imageUrl,
                  let url = raw.upgradedToHTTPS
            else { continue }
            result[episode] = url
        }
        return result
    }

    /// Only "real" trailers/clips — without per-episode previews (those live
    /// in EpisodeGrid, not TrailersSection).
    static func trailerVideos(from videos: [AnimeVideoREST]) -> [AnimeVideoREST] {
        videos.filter { $0.kind?.lowercased() != "episode_preview" }
    }
}
