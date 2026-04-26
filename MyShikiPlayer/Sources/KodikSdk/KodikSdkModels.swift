//
//  KodikSdkModels.swift
//  MyShikiPlayer
//

import Foundation

enum KodikTranslationKind: String, Codable {
    case voice
    case subtitles
}

struct KodikTranslation: Identifiable, Hashable, Codable {
    let id: Int
    let title: String
    let kind: KodikTranslationKind?
}

struct KodikCatalogEntry: Hashable, Codable {
    let translation: KodikTranslation
    let episodes: [Int: String]
    let fallbackLink: String?

    /// Link to the requested episode. If this dub has an episodes map
    /// (which means it is a series), return the strictly episode-specific
    /// link and never fall back to the generic `serial/N/...` URL — `/ftor`
    /// returns 404 on it and breaks resolution of neighboring dubs.
    /// `fallbackLink` is only needed for movies, where episodes is empty.
    func link(for episode: Int) -> String? {
        if !episodes.isEmpty {
            return episodes[episode]
        }
        return fallbackLink
    }
}

struct KodikSearchResponse: Decodable {
    let results: [KodikMaterial]
}

struct KodikMaterial: Decodable {
    struct Translation: Decodable {
        let id: Int?
        let title: String?
        let type: String?
    }

    let translation: Translation?
    let episodes: [String: KodikEpisodePayload]?
    let seasons: [String: KodikSeasonPayload]?
    let link: String?
    let blockedSeasons: KodikBlockedSeasons?

    enum CodingKeys: String, CodingKey {
        case translation
        case episodes
        case seasons
        case link
        case blockedSeasons = "blocked_seasons"
    }
}

struct KodikSeasonPayload: Decodable {
    let episodes: [String: KodikEpisodePayload]?
}

enum KodikEpisodePayload: Decodable {
    case link(String)
    case object(EpisodeObject)

    struct EpisodeObject: Decodable {
        let link: String?
    }

    var link: String? {
        switch self {
        case .link(let value):
            return value
        case .object(let obj):
            return obj.link
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .link(value)
            return
        }
        self = .object(try container.decode(EpisodeObject.self))
    }
}

/// Shape of `blocked_seasons` from the Kodik response:
/// - string `"all"` — the whole material is blocked
/// - object `{ "5": "all", "7": ["1","2","3"] }` — partial block
enum KodikBlockedSeasons: Decodable {
    case all
    case map([String: SeasonValue])

    enum SeasonValue: Decodable {
        case all
        case episodes(Set<String>)

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self), s.lowercased() == "all" {
                self = .all
                return
            }
            let list = try c.decode([String].self)
            self = .episodes(Set(list))
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self), s.lowercased() == "all" {
            self = .all
            return
        }
        self = .map(try c.decode([String: SeasonValue].self))
    }
}
