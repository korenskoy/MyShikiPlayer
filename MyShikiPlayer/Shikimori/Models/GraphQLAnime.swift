//
//  GraphQLAnime.swift
//  MyShikiPlayer
//

import Foundation

struct GraphQLPoster: Codable, Sendable, Equatable {
    let id: String?
    let originalUrl: String?
    let mainUrl: String?
}

struct GraphQLExternalLink: Codable, Sendable, Equatable {
    let id: String?
    let kind: String?
    let url: String?
    let createdAt: String?
    let updatedAt: String?
}

struct GraphQLGenre: Codable, Sendable, Equatable {
    let id: String?
    let name: String?
    let russian: String?
    let kind: String?
}

struct GraphQLStudio: Codable, Sendable, Equatable {
    let id: String?
    let name: String?
    let imageUrl: String?
}

struct GraphQLDateParts: Codable, Sendable, Equatable {
    let year: Int?
    let month: Int?
    let day: Int?
    let date: String?
}

struct GraphQLAnimeSummary: Codable, Sendable, Equatable {
    let id: Int
    let malId: Int?
    let name: String?
    let russian: String?
    let licenseNameRu: String?
    let english: String?
    let japanese: String?
    let synonyms: [String]?
    let kind: String?
    let rating: String?
    let score: Double?
    let status: String?
    let episodes: Int?
    let episodesAired: Int?
    let duration: Int?
    let airedOn: GraphQLDateParts?
    let releasedOn: GraphQLDateParts?
    let url: String?
    let season: String?
    let nextEpisodeAt: Date?
    let isCensored: Bool?
    let poster: GraphQLPoster?
    let externalLinks: [GraphQLExternalLink]?
    let genres: [GraphQLGenre]?
    let studios: [GraphQLStudio]?

    enum CodingKeys: String, CodingKey {
        case id
        case malId
        case name
        case russian
        case licenseNameRu
        case english
        case japanese
        case synonyms
        case kind
        case rating
        case score
        case status
        case episodes
        case episodesAired
        case duration
        case airedOn
        case releasedOn
        case url
        case season
        case nextEpisodeAt
        case isCensored
        case poster
        case externalLinks
        case genres
        case studios
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeLossyInt(forKey: .id)
        malId = try c.decodeLossyIntIfPresent(forKey: .malId)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        russian = try c.decodeIfPresent(String.self, forKey: .russian)
        licenseNameRu = try c.decodeIfPresent(String.self, forKey: .licenseNameRu)
        english = try c.decodeIfPresent(String.self, forKey: .english)
        japanese = try c.decodeIfPresent(String.self, forKey: .japanese)
        synonyms = try c.decodeIfPresent([String].self, forKey: .synonyms)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        rating = try c.decodeIfPresent(String.self, forKey: .rating)
        score = try c.decodeIfPresent(Double.self, forKey: .score)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        episodes = try c.decodeIfPresent(Int.self, forKey: .episodes)
        episodesAired = try c.decodeIfPresent(Int.self, forKey: .episodesAired)
        duration = try c.decodeIfPresent(Int.self, forKey: .duration)
        airedOn = try c.decodeIfPresent(GraphQLDateParts.self, forKey: .airedOn)
        releasedOn = try c.decodeIfPresent(GraphQLDateParts.self, forKey: .releasedOn)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        season = try c.decodeIfPresent(String.self, forKey: .season)
        nextEpisodeAt = try c.decodeIfPresent(Date.self, forKey: .nextEpisodeAt)
        isCensored = try c.decodeIfPresent(Bool.self, forKey: .isCensored)
        poster = try c.decodeIfPresent(GraphQLPoster.self, forKey: .poster)
        externalLinks = try c.decodeIfPresent([GraphQLExternalLink].self, forKey: .externalLinks)
        genres = try c.decodeIfPresent([GraphQLGenre].self, forKey: .genres)
        studios = try c.decodeIfPresent([GraphQLStudio].self, forKey: .studios)
    }
}

struct GraphQLDataAnimes: Codable, Sendable {
    let animes: [GraphQLAnimeSummary]?
}

struct GraphQLAnimesEnvelope: Codable, Sendable {
    let data: GraphQLDataAnimes?
    let errors: [GraphQLErrorMessage]?
}

private extension KeyedDecodingContainer {
    func decodeLossyInt(forKey key: Key) throws -> Int {
        if let intValue = try? decode(Int.self, forKey: key) {
            return intValue
        }
        let stringValue = try decode(String.self, forKey: key)
        guard let intValue = Int(stringValue) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected Int or numeric String")
        }
        return intValue
    }

    func decodeLossyIntIfPresent(forKey key: Key) throws -> Int? {
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return intValue
        }
        guard let stringValue = try decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return Int(stringValue)
    }
}
