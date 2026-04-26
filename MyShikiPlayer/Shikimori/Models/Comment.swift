//
//  Comment.swift
//  MyShikiPlayer
//
//  /api/comments?commentable_type=Topic&commentable_id=X.
//  Shikimori returns both `body` (BBCode) and `html_body` (HTML-converted).
//  htmlBody is enough for us — easier to parse.
//

import Foundation

struct TopicComment: Codable, Sendable, Equatable {
    let id: Int
    let commentableId: Int?
    let commentableType: String?
    let body: String?
    let htmlBody: String?
    let user: TopicUser?
    let createdAt: Date?
    let updatedAt: Date?
    let isOffended: Bool?
    let isSummary: Bool?
}
