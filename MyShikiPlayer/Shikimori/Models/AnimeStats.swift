//
//  AnimeStats.swift
//  MyShikiPlayer
//
//  Aggregated statistics from Shikimori GraphQL: distribution of scores
//  and statuses across users' lists. REST does not return this data.
//

import Foundation

struct AnimeScoresStat: Codable, Sendable, Equatable, Hashable {
    let score: Int
    let count: Int
}

struct AnimeStatusesStat: Codable, Sendable, Equatable, Hashable {
    /// Shikimori returns the status as a string: watching / completed / planned / …
    let status: String
    let count: Int
}

struct GraphQLAnimeStatsEntry: Codable, Sendable {
    /// Shikimori GraphQL returns id as a string — decode as String to avoid
    /// breaking on type mismatches; this id is not used in the code.
    let id: String?
    let poster: GraphQLPoster?
    let scoresStats: [AnimeScoresStat]?
    let statusesStats: [AnimeStatusesStat]?
}

struct GraphQLAnimeStatsData: Codable, Sendable {
    let animes: [GraphQLAnimeStatsEntry]?
}

struct GraphQLAnimeStatsEnvelope: Codable, Sendable {
    let data: GraphQLAnimeStatsData?
    let errors: [GraphQLErrorMessage]?
}
