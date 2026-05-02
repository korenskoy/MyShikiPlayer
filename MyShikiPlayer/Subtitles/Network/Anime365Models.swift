//
//  Anime365Models.swift
//  MyShikiPlayer
//

import Foundation

// MARK: - Series

struct Anime365Series: Codable, Sendable {
  let id: Int
  let myAnimeListId: Int?
  let title: String?
  let episodes: [Anime365EpisodeSummary]?

  enum CodingKeys: String, CodingKey {
    case id
    case myAnimeListId
    case title
    case episodes
  }
}

// MARK: - Episode summary (appears inside series?fields=episodes)

struct Anime365EpisodeSummary: Codable, Sendable {
  let id: Int
  let isActive: Int
  let episodeInt: String
  let episodeType: String

  enum CodingKeys: String, CodingKey {
    case id
    case isActive
    case episodeInt
    case episodeType
  }
}

// MARK: - Episode detail (from /episodes/{id})

struct Anime365EpisodeDetail: Codable, Sendable {
  let id: Int
  let isActive: Int
  let episodeInt: String
  let episodeType: String
  let translations: [Anime365Translation]

  enum CodingKeys: String, CodingKey {
    case id
    case isActive
    case episodeInt
    case episodeType
    case translations
  }
}

// MARK: - Translation

struct Anime365Translation: Codable, Sendable {
  let id: Int
  let type: String
  let typeKind: String
  let typeLang: String?
  let isActive: Int
  let title: String?
  let authorsSummary: String?

  enum CodingKeys: String, CodingKey {
    case id
    case type
    case typeKind
    case typeLang
    case isActive
    case title
    case authorsSummary
  }
}

// MARK: - Language filter

enum Anime365LangFilter: String, Sendable {
  case all
  case subRu = "subru"
  case subEn = "suben"
}

// MARK: - Subtitle candidate (output of the search pipeline)

struct SubtitleCandidate: Sendable {
  let translationId: Int
  let type: String
  let typeKind: String
  let title: String?
  let authorsSummary: String?
  let assURL: URL
  let vttURL: URL
}

// MARK: - Search result (full pipeline output)

struct SubtitleSearchResult: Sendable {
  let shikimoriId: Int
  let requestedEpisode: Int
  let seriesId: Int
  let seriaId: Int
  let title: String?
  let subtitles: [SubtitleCandidate]
}

// MARK: - Wrapped-response helper

/// Decodes a response that may be either `{data: T}` or a bare `T`.
struct Anime365DataEnvelope<T: Decodable>: Decodable {
  let value: T

  init(from decoder: Decoder) throws {
    if let container = try? decoder.container(keyedBy: DataKey.self),
       let nested = try? container.decode(T.self, forKey: .data) {
      value = nested
    } else {
      value = try T(from: decoder)
    }
  }

  private enum DataKey: String, CodingKey {
    case data
  }
}
