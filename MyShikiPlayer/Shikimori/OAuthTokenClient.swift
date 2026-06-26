//
//  OAuthTokenClient.swift
//  MyShikiPlayer
//

import Foundation

/// Exchanges authorization codes and refreshes tokens. Uses `User-Agent` only (no Bearer on `/oauth/token`).
final class OAuthTokenClient: Sendable {
    private let configuration: ShikimoriConfiguration
    private let session: URLSession

    init(configuration: ShikimoriConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        self.session = session ?? Self.redirectPreservingSession
    }

    /// Shared session that keeps POST + body across redirects on `/oauth/token`.
    /// Shikimori mirror hosts (e.g. .one/.me → .io) answer with a 301, and
    /// URLSession's default behaviour downgrades POST→GET and drops the body —
    /// the redirected request then hits `GET /oauth/token` = 404. The delegate
    /// re-applies the original method and body so the token request survives.
    private static let redirectPreservingSession = URLSession(
        configuration: .default,
        delegate: OAuthRedirectPreservingDelegate(),
        delegateQueue: nil
    )

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
        let method = req.httpMethod ?? "-"
        NetworkLogStore.shared.logOAuthEvent("token_request \(method) \(NetworkLogStore.maskedURLString(tokenURL))")

        let startedAt = Date()
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw ShikimoriAPIError.invalidResponse }
            let ms = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
            NetworkLogStore.shared.logOAuthEvent("token_response \(method) \(http.statusCode) \(ms)ms \(data.count)B")
            guard (200..<300).contains(http.statusCode) else {
                throw ShikimoriAPIError.httpStatus(code: http.statusCode, body: data.isEmpty ? nil : data)
            }
            do {
                return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
            } catch {
                throw ShikimoriAPIError.decoding(underlying: error, body: data)
            }
        } catch {
            NetworkLogStore.shared.logOAuthEvent("token_failed \(method) \(error.localizedDescription)")
            throw error
        }
    }
}

/// Decides whether a redirected `/oauth/token` POST may keep its credentialed
/// body (client_secret / code / refresh_token).
enum OAuthRedirectPolicy {
    /// Known Shikimori mirror hosts the token endpoint legitimately bounces
    /// between (e.g. `.one`/`.me` 301 to `.io`).
    static let shikimoriMirrors = ["shikimori.io", "shikimori.one", "shikimori.me", "shikimori.org"]

    /// True only when the redirect stays on HTTPS and targets either the same
    /// host or a known Shikimori mirror. Forwarding the body anywhere else
    /// would leak OAuth secrets to a third party, so those redirects are
    /// refused entirely.
    static func mayForwardCredentials(from original: URL?, to target: URL) -> Bool {
        guard target.scheme == "https", let host = target.host?.lowercased() else { return false }
        if let originalHost = original?.host?.lowercased(), originalHost == host { return true }
        return shikimoriMirrors.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

/// Preserves the HTTP method and body when Shikimori 301-redirects `/oauth/token`
/// between mirror hosts — without it URLSession silently turns the POST into a
/// GET (which 404s). Credentials (client_secret / refresh_token) are only
/// re-attached when the target is known-safe (`OAuthRedirectPolicy` mirrors,
/// same host, or a user-trusted host); an unknown HTTPS host prompts the user
/// for explicit consent before forwarding, and anything else is refused.
private final class OAuthRedirectPreservingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let original = task.originalRequest, original.httpMethod == "POST" else {
            completionHandler(request) // non-POST: keep default redirect handling
            return
        }
        guard let target = request.url, target.scheme == "https",
              let host = target.host?.lowercased(), !host.isEmpty else {
            completionHandler(nil) // never forward creds over non-HTTPS / host-less
            return
        }
        let preserved = Self.preserving(original: original, redirect: request)
        if OAuthRedirectPolicy.mayForwardCredentials(from: original.url, to: target)
            || TrustedOAuthHostsStore.contains(host) {
            completionHandler(preserved)
            return
        }
        // Unknown host — Shikimori mirrors get banned and replaced, so this may
        // be a legitimate new one. Ask the user (with friction) before sending
        // the client_secret / refresh_token there.
        let fromHost = original.url?.host ?? ""
        Task {
            let approved = await OAuthRedirectConsentCoordinator.shared.requestConsent(
                host: host, fromHost: fromHost
            )
            completionHandler(approved ? preserved : nil)
        }
    }

    private static func preserving(original: URLRequest, redirect: URLRequest) -> URLRequest {
        var preserved = redirect
        preserved.httpMethod = original.httpMethod
        preserved.httpBody = original.httpBody
        for header in ["Content-Type", "User-Agent"] {
            if let value = original.value(forHTTPHeaderField: header) {
                preserved.setValue(value, forHTTPHeaderField: header)
            }
        }
        return preserved
    }
}
