//
//  ShikimoriGraphQLQueries.swift
//  MyShikiPlayer
//

import Foundation

enum ShikimoriGraphQLQueries {
    static let currentUser = #"""
    query CurrentUser {
      currentUser {
        id
        nickname
      }
    }
    """#

    /// Matches public playground shape; filters via variables.
    static let animesSearch = #"""
    query AnimesSearch($search: String, $limit: Int, $kind: String) {
      animes(search: $search, limit: $limit, kind: $kind) {
        id
        malId
        name
        russian
        licenseNameRu
        english
        japanese
        synonyms
        kind
        rating
        score
        status
        episodes
        episodesAired
        duration
        airedOn { year month day date }
        releasedOn { year month day date }
        url
        season
        nextEpisodeAt
        isCensored
        poster { id originalUrl mainUrl }
        externalLinks { id kind url createdAt updatedAt }
        genres { id name russian kind }
        studios { id name imageUrl }
      }
    }
    """#

    /// Fetch score + status distribution + the real poster URL by id.
    /// REST endpoint sometimes returns `/assets/globals/missing_preview.jpg`
    /// even when the title has a poster — we fetch it here.
    static let animeStats = #"""
    query AnimeStats($id: String!) {
      animes(ids: $id, limit: 1) {
        id
        poster { id originalUrl mainUrl }
        scoresStats { score count }
        statusesStats { status count }
      }
    }
    """#

    /// Query anime metadata by explicit id list (ids as comma-separated string).
    /// The field set must cover enrichment for all lists: continue watching
    /// (needs episodesAired for the progress bar), home sections (score for
    /// the badge). If you add a new UI field — check here first.
    static let animesByIds = #"""
    query AnimesByIds($ids: String, $search: String, $limit: Int, $kind: AnimeKindString) {
      animes(ids: $ids, search: $search, limit: $limit, kind: $kind) {
        id
        name
        russian
        kind
        score
        status
        episodes
        episodesAired
        airedOn { date }
        releasedOn { date }
        poster { originalUrl mainUrl }
      }
    }
    """#
}

struct AnimesSearchVariables: Encodable, Sendable {
    let search: String
    let limit: Int
    let kind: String?
}

struct AnimesByIdsVariables: Encodable, Sendable {
    let ids: String?
    let search: String?
    let limit: Int
    let kind: AnimeKindString?
}

struct AnimeStatsVariables: Encodable, Sendable {
    let id: String
}

enum AnimeKindString: String, Encodable, Sendable {
    case tv
    case movie
    case ova
    case ona
    case special
    case music
    case tv13 = "tv_13"
    case tv24 = "tv_24"
    case tv48 = "tv_48"
}
