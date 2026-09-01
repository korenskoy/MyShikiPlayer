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
  /// Anime365 sends this as a JSON number; older responses sent a string. Accept both —
  /// a type mismatch here drops the whole episode list and the search reports
  /// "episode not found" for every title.
  let episodeInt: Double?
  let episodeType: String

  enum CodingKeys: String, CodingKey {
    case id
    case isActive
    case episodeInt
    case episodeType
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(Int.self, forKey: .id)
    isActive = try container.decode(Int.self, forKey: .isActive)
    episodeType = try container.decode(String.self, forKey: .episodeType)
    if let number = try? container.decode(Double.self, forKey: .episodeInt) {
      episodeInt = number
    } else {
      episodeInt = (try? container.decode(String.self, forKey: .episodeInt)).flatMap(Double.init)
    }
  }
}

// MARK: - Episode detail (from /episodes/{id})

struct Anime365EpisodeDetail: Codable, Sendable {
  let id: Int
  let translations: [Anime365Translation]

  enum CodingKeys: String, CodingKey {
    case id
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
    // Only the absence of `data` justifies the bare-payload fallback. Swallowing a
    // decode failure here turns a type mismatch into silently empty data.
    if let container = try? decoder.container(keyedBy: DataKey.self), container.contains(.data) {
      value = try container.decode(T.self, forKey: .data)
    } else {
      value = try T(from: decoder)
    }
  }

  private enum DataKey: String, CodingKey {
    case data
  }
}
