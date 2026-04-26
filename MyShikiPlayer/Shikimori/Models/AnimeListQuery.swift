//
//  AnimeListQuery.swift
//  MyShikiPlayer
//

import Foundation

struct AnimeListQuery: Sendable {
    var page: Int? = nil
    var limit: Int? = nil
    var order: String? = nil
    var kind: String? = nil
    var status: String? = nil
    var season: String? = nil
    var score: Int? = nil
    var duration: String? = nil
    var rating: String? = nil
    var genre: String? = nil
    var genreV2: String? = nil
    var studio: String? = nil
    var franchise: String? = nil
    var censored: Bool? = nil
    var mylist: String? = nil
    var ids: String? = nil
    var excludeIds: String? = nil
    var search: String? = nil
    var origin: String? = nil
    var licensed: Bool? = nil
    var licensor: String? = nil

    nonisolated init() {}

    func queryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let page { items.append(URLQueryItem(name: "page", value: "\(page)")) }
        if let limit { items.append(URLQueryItem(name: "limit", value: "\(limit)")) }
        if let order { items.append(URLQueryItem(name: "order", value: order)) }
        if let kind { items.append(URLQueryItem(name: "kind", value: kind)) }
        if let status { items.append(URLQueryItem(name: "status", value: status)) }
        if let season { items.append(URLQueryItem(name: "season", value: season)) }
        if let score { items.append(URLQueryItem(name: "score", value: "\(score)")) }
        if let duration { items.append(URLQueryItem(name: "duration", value: duration)) }
        if let rating { items.append(URLQueryItem(name: "rating", value: rating)) }
        if let genre { items.append(URLQueryItem(name: "genre", value: genre)) }
        if let genreV2 { items.append(URLQueryItem(name: "genre_v2", value: genreV2)) }
        if let studio { items.append(URLQueryItem(name: "studio", value: studio)) }
        if let franchise { items.append(URLQueryItem(name: "franchise", value: franchise)) }
        if let censored { items.append(URLQueryItem(name: "censored", value: censored ? "true" : "false")) }
        if let mylist { items.append(URLQueryItem(name: "mylist", value: mylist)) }
        if let ids { items.append(URLQueryItem(name: "ids", value: ids)) }
        if let excludeIds { items.append(URLQueryItem(name: "exclude_ids", value: excludeIds)) }
        if let search { items.append(URLQueryItem(name: "search", value: search)) }
        if let origin { items.append(URLQueryItem(name: "origin", value: origin)) }
        if let licensed { items.append(URLQueryItem(name: "licensed", value: licensed ? "true" : "false")) }
        if let licensor { items.append(URLQueryItem(name: "licensor", value: licensor)) }
        return items
    }
}

struct UserRatesListQuery: Sendable {
    var userId: Int? = nil
    var targetId: Int? = nil
    var targetType: String? = nil
    var status: String? = nil
    var page: Int? = nil
    var limit: Int? = nil

    nonisolated init() {}

    func queryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let userId { items.append(URLQueryItem(name: "user_id", value: "\(userId)")) }
        if let targetId { items.append(URLQueryItem(name: "target_id", value: "\(targetId)")) }
        if let targetType { items.append(URLQueryItem(name: "target_type", value: targetType)) }
        if let status { items.append(URLQueryItem(name: "status", value: status)) }
        if let page { items.append(URLQueryItem(name: "page", value: "\(page)")) }
        if let limit { items.append(URLQueryItem(name: "limit", value: "\(limit)")) }
        return items
    }
}
