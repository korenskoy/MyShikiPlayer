//
//  CurrentUser.swift
//  MyShikiPlayer
//

import Foundation

struct CurrentUser: Codable, Sendable, Equatable {
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
}

struct UserImageSet: Codable, Sendable, Equatable {
    let x160: String?
    let x148: String?
    let x80: String?
    let x64: String?
    let x48: String?
    let x32: String?
    let x16: String?
}

struct GraphQLCurrentUserData: Codable, Sendable {
    let currentUser: GraphQLCurrentUser?
}

struct GraphQLCurrentUserEnvelope: Codable, Sendable {
    let data: GraphQLCurrentUserData?
    let errors: [GraphQLErrorMessage]?
}

struct GraphQLCurrentUser: Codable, Sendable, Equatable {
    let id: String
    let nickname: String
}
