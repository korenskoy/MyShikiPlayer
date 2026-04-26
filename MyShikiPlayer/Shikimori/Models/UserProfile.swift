//
//  UserProfile.swift
//  MyShikiPlayer
//
//  Full profile from /api/users/{id}. Superset of CurrentUser + stats.
//  CurrentUser is kept for auth (minimal, not coupled to decoding of the
//  stats block, which may break in the future).
//

import Foundation

struct UserProfile: Codable, Sendable, Equatable {
    let id: Int
    let nickname: String
    let avatar: String?
    let image: UserImageSet?
    let lastOnlineAt: Date?
    let url: String?
    let name: String?
    let sex: String?
    let website: String?
    let birthOn: String?
    let fullYears: Int?
    let locale: String?
    let commonInfo: [String]?
    let stats: UserStats?
}

struct UserStats: Codable, Sendable, Equatable {
    /// Distribution of titles by status (watching / planned / completed / …).
    let statuses: UserStatsByKind?
    /// Score histogram ("10" → N, "9" → N, …).
    let scores: UserStatsByKind?
    /// Distribution by kind (tv / movie / ova / …).
    let types: UserStatsByKind?
}

struct UserStatsByKind: Codable, Sendable, Equatable {
    let anime: [UserStatBucket]?
}

/// Universal cell in stats sections: (name, value/size).
/// Shikimori sends value/size in different sections, plus grouped_id in statuses.
struct UserStatBucket: Codable, Sendable, Equatable {
    let id: Int?
    let groupedId: String?
    let name: String?
    let size: Int?
    let value: Int?
    let type: String?

    /// Number — bucket size, regardless of which key the API used.
    var count: Int { size ?? value ?? 0 }
}

/// `/api/users/{id}/favourites` — litmus section: avatars + covers.
/// We only take the anime collection.
struct UserFavourites: Codable, Sendable, Equatable {
    let animes: [UserFavouriteAnime]?
}

struct UserFavouriteAnime: Codable, Sendable, Equatable {
    let id: Int
    let name: String?
    let russian: String?
    /// In this endpoint `image` is a single string, not a `{original, preview, …}` object.
    let image: String?
    let url: String?
}
