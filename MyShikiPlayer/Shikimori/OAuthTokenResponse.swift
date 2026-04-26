//
//  OAuthTokenResponse.swift
//  MyShikiPlayer
//

import Foundation

struct OAuthTokenResponse: Decodable, Sendable {
    let accessToken: String
    let tokenType: String?
    let expiresIn: Int?
    let refreshToken: String?
    let createdAt: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case createdAt = "created_at"
    }
}

struct OAuthCredential: Codable, Sendable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?

    init(accessToken: String, refreshToken: String?, expiresAt: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    init(response: OAuthTokenResponse, defaultLifetime: TimeInterval = 86400) {
        self.accessToken = response.accessToken
        self.refreshToken = response.refreshToken
        if let sec = response.expiresIn {
            self.expiresAt = Date().addingTimeInterval(TimeInterval(sec))
        } else {
            self.expiresAt = Date().addingTimeInterval(defaultLifetime)
        }
    }
}
