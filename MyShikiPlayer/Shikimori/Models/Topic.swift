//
//  Topic.swift
//  MyShikiPlayer
//
//  /api/topics: discussions, reviews, news. Universal model — fields
//  cover both "Topic" (generic) and "Topics::EntryTopic" (anime thread).
//

import Foundation

struct Topic: Codable, Sendable, Equatable {
    let id: Int
    let topicTitle: String?
    let body: String?
    let htmlBody: String?
    let createdAt: Date?
    let commentsCount: Int?
    let forum: TopicForum?
    let user: TopicUser?
    let type: String?
    /// If `linkedType == "Anime"`, `linked` contains the anime card.
    let linkedId: Int?
    let linkedType: String?
    let linked: TopicLinked?
}

struct TopicForum: Codable, Sendable, Equatable {
    let id: Int?
    let name: String?
    let permalink: String?
}

struct TopicUser: Codable, Sendable, Equatable {
    let id: Int?
    let nickname: String?
    let avatar: String?
    let image: UserImageSet?
    let lastOnlineAt: Date?
    let url: String?
}

/// Focus is on Anime-linked topics. Other linked types (Review, Club, …)
/// return roughly the same shape, but without `image`.
struct TopicLinked: Codable, Sendable, Equatable {
    let id: Int?
    let name: String?
    let russian: String?
    let image: AnimeImageURLs?
    let url: String?
    let kind: String?
    let score: String?
}
