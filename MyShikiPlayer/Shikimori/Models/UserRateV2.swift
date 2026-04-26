//
//  UserRateV2.swift
//  MyShikiPlayer
//

import Foundation

struct UserRateV2: Codable, Sendable, Equatable {
    let id: Int
    let userId: Int
    let targetId: Int
    let targetType: String
    let score: Int
    let status: String
    let rewatches: Int
    let episodes: Int
    let volumes: Int
    let chapters: Int
    let text: String?
    let textHtml: String?
    let createdAt: Date
    let updatedAt: Date
}

/// API expects string numbers inside `user_rate`; use `JSONEncoder.keyEncodingStrategy = .convertToSnakeCase`.
struct UserRateV2CreateBody: Encodable, Sendable {
    struct Payload: Encodable, Sendable {
        let userId: String
        let targetId: String
        let targetType: String
        let status: String?
        let score: String?
        let chapters: String?
        let episodes: String?
        let volumes: String?
        let rewatches: String?
        let text: String?
    }

    let userRate: Payload
}

struct UserRateV2UpdateBody: Encodable, Sendable {
    struct Payload: Encodable, Sendable {
        let chapters: String?
        let episodes: String?
        let volumes: String?
        let rewatches: String?
        let score: String?
        let status: String?
        let text: String?
    }

    let userRate: Payload
}
