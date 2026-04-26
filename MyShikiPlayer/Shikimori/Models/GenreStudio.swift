//
//  GenreStudio.swift
//  MyShikiPlayer
//

import Foundation

/// Reference entry returned by `GET /api/genres`.
struct Genre: Codable, Sendable, Equatable, Identifiable {
    let id: Int
    let name: String
    let russian: String?
    let kind: String?
    let entryType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case russian
        case kind
        case entryType = "entry_type"
    }

    var displayName: String {
        if let russian, !russian.isEmpty { return russian }
        return name
    }
}

/// Reference entry returned by `GET /api/studios`.
struct Studio: Codable, Sendable, Equatable, Identifiable {
    let id: Int
    let name: String
    let filteredName: String?
    let real: Bool?
    let image: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case filteredName = "filtered_name"
        case real
        case image
    }

    var displayName: String {
        if let filteredName, !filteredName.isEmpty { return filteredName }
        return name
    }
}
