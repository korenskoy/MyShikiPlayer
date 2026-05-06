//
//  OAuthTokenClient.swift
//  MyShikiPlayer
//

import Foundation

/// Exchanges authorization codes and refreshes tokens. Uses `User-Agent` only (no Bearer on `/oauth/token`).
final class OAuthTokenClient: Sendable {
    private let configuration: ShikimoriConfiguration
    private let session: URLSession

    init(configuration: ShikimoriConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    private var tokenURL: URL {
        configuration.oauthBaseURL.appendingPathComponent("oauth/token")
    }

    func exchangeAuthorizationCode(_ code: String) async throws -> OAuthTokenResponse {
        try await postToken(fields: [
            "grant_type": "authorization_code",
            "client_id": configuration.clientId,
            "client_secret": configuration.clientSecret,
            "code": code,
            "redirect_uri": configuration.redirectURI,
        ])
    }

    func refresh(_ refreshToken: String) async throws -> OAuthTokenResponse {
        try await postToken(fields: [
            "grant_type": "refresh_token",
            "client_id": configuration.clientId,
            "client_secret": configuration.clientSecret,
            "refresh_token": refreshToken,
        ])
    }

    private func postToken(fields: [String: String]) async throws -> OAuthTokenResponse {
        var c = URLComponents()
        c.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        let body = Data((c.percentEncodedQuery ?? "").utf8)

        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(configuration.userAgentHeaderValue, forHTTPHeaderField: "User-Agent")
        NetworkLogStore.shared.logOAuthEvent("token_request \(NetworkLogStore.maskedURLString(tokenURL))")

        let startedAt = Date()
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw ShikimoriAPIError.invalidResponse }
            let ms = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
            NetworkLogStore.shared.logOAuthEvent("token_response \(http.statusCode) \(ms)ms \(data.count)B")
            guard (200..<300).contains(http.statusCode) else {
                throw ShikimoriAPIError.httpStatus(code: http.statusCode, body: data.isEmpty ? nil : data)
            }
            do {
                return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
            } catch {
                throw ShikimoriAPIError.decoding(underlying: error, body: data)
            }
        } catch {
            NetworkLogStore.shared.logOAuthEvent("token_failed \(error.localizedDescription)")
            throw error
        }
    }
}
