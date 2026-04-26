//
//  AnimeREST.swift
//  MyShikiPlayer
//

import Foundation

struct AnimeImageURLs: Codable, Sendable, Equatable {
    let original: String?
    let preview: String?
    let x96: String?
    let x48: String?
}

struct AnimeListItem: Codable, Sendable, Equatable {
    let id: Int
    let name: String
    let russian: String?
    let image: AnimeImageURLs?
    let url: String?
    let kind: String?
    let score: String?
    let status: String?
    let episodes: Int?
    let episodesAired: Int?
    let airedOn: String?
    let releasedOn: String?
}

struct AnimeDetail: Codable, Sendable, Equatable {
    let id: Int
    let name: String
    let russian: String?
    let image: AnimeImageURLs?
    let url: String?
    let kind: String?
    let score: String?
    let status: String?
    let episodes: Int?
    let episodesAired: Int?
    let airedOn: String?
    let releasedOn: String?
    let rating: String?
    let english: [String?]?
    let japanese: [String?]?
    let synonyms: [String]?
    let licenseNameRu: String?
    let duration: Int?
    let description: String?
    let descriptionHtml: String?
    let descriptionSource: String?
    let franchise: String?
    let favoured: Bool?
    let anons: Bool?
    let ongoing: Bool?
    let threadId: Int?
    let topicId: Int?
    let myanimelistId: Int?
    let updatedAt: Date?
    let nextEpisodeAt: Date?
    let fansubbers: [String]?
    let fandubbers: [String]?
    let licensors: [String]?
    let genres: [AnimeGenreREST]?
    let studios: [AnimeStudioREST]?
    let videos: [AnimeVideoREST]?
    let screenshots: [AnimeScreenshotREST]?
    let userRate: UserRateREST?
}

extension AnimeDetail {
    /// Anons on Shikimori — there are no episodes yet, the player and sources are not connected.
    var blocksPlaybackBecauseAnon: Bool {
        if anons == true { return true }
        guard let status else { return false }
        return status.caseInsensitiveCompare("anons") == .orderedSame
    }

    /// Upper bound of episode number for the selector when the Kodik episode list is unavailable (as in the "Episodes" block on Shikimori).
    var episodeCountForPickerFallback: Int? {
        let planned = episodes ?? 0
        let aired = episodesAired ?? 0
        if ongoing == true {
            if aired > 0 { return aired }
            if planned > 0 { return planned }
            return nil
        }
        if planned > 0 { return planned }
        if aired > 0 { return aired }
        return nil
    }
}

struct AnimeGenreREST: Codable, Sendable, Equatable {
    let id: Int?
    let name: String?
    let russian: String?
    let kind: String?
}

struct AnimeStudioREST: Codable, Sendable, Equatable {
    let id: Int?
    let name: String?
    let image: String?
    let imageUrl: String?
}

struct AnimeVideoREST: Codable, Sendable, Equatable {
    let id: Int?
    let url: String?
    /// Thumbnail for the video (YouTube `hqdefault.jpg`, etc.). Returned via HTTP —
    /// when used, we force https.
    let imageUrl: String?
    let playerUrl: String?
    let name: String?
    /// "pv", "op", "ed", "cm", "trailer", "promo", **"episode_preview"**, etc.
    let kind: String?
    let hosting: String?
}

struct AnimeScreenshotREST: Codable, Sendable, Equatable {
    let original: String?
    let preview: String?
}

/// Embedded in anime detail when authorized (snake_case `user_rate` from API).
struct UserRateREST: Codable, Sendable, Equatable {
    let id: Int?
    let score: Int?
    let status: String?
    let episodes: Int?
    let rewatches: Int?
}
