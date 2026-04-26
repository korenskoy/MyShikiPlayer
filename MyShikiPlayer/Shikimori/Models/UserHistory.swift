//
//  UserHistory.swift
//  MyShikiPlayer
//
//  /api/users/{id}/history — recent user actions.
//  Used in the friend activity feed.
//

import Foundation

struct UserHistoryEntry: Codable, Sendable, Equatable, Identifiable {
    let id: Int
    let createdAt: Date?
    /// Raw text description from Shikimori. Usually HTML with an action label,
    /// like "<a>Watched episode 3</a>". For previews use stripHTML + trim.
    let description: String?
    let target: HistoryTarget?
}

/// Target in history — anime or manga. Shikimori returns exactly the fields
/// known to both models: id / name / russian / image / url / kind.
struct HistoryTarget: Codable, Sendable, Equatable {
    let id: Int
    let name: String?
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

/// /api/users/{id}/friends — minimum fields needed for avatar + navigation.
struct UserFriend: Codable, Sendable, Equatable, Identifiable {
    let id: Int
    let nickname: String
    let avatar: String?
    let image: UserImageSet?
    let lastOnlineAt: Date?
    let url: String?
}
