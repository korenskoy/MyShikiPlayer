//
//  ShikimoriHTTPClient.swift
//  MyShikiPlayer
//

import Combine
import Foundation

protocol ShikimoriHTTPClientProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

actor RequestThrottler {
    /// Process-wide throttler sized to Shikimori's documented limits
    /// (5 rps + 90 rpm). Every `ShikimoriHTTPClient` shares this instance
    /// by default so REST and GraphQL calls combined respect a single quota
    /// — without it each client gated its own 5 rps in isolation.
    static let shared = RequestThrottler(
        minInterval: 0.2,
        windowDuration: 60,
        maxRequestsInWindow: 90
    )

    private var lastRequest: Date = .distantPast
    /// Timestamps of grants that still fall inside the rolling
    /// `windowDuration`. Expired entries are dropped on each call.
    private var recentGrants: [Date] = []
    private let minInterval: TimeInterval
    private let windowDuration: TimeInterval
    private let maxRequestsInWindow: Int

    init(
        minInterval: TimeInterval = 0.2,
        windowDuration: TimeInterval = 60,
        maxRequestsInWindow: Int = 90
    ) {
        self.minInterval = minInterval
        self.windowDuration = windowDuration
        self.maxRequestsInWindow = maxRequestsInWindow
    }

    func waitTurn() async {
        // Stage 1 — per-second minimum interval.
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRequest)
        if elapsed < minInterval {
            let ns = UInt64((minInterval - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
        }

        // Stage 2 — rolling window cap. Drop expired stamps, then if the
        // window is full sleep until the oldest stamp falls out. Re-evaluate
        // in a loop because other tasks waiting on this actor may have
        // grabbed slots while we slept.
        while true {
            let windowStart = Date().addingTimeInterval(-windowDuration)
            recentGrants.removeAll { $0 < windowStart }
            if recentGrants.count < maxRequestsInWindow { break }
            guard let oldest = recentGrants.first else { break }
            let wakeup = oldest.addingTimeInterval(windowDuration)
            let toSleep = wakeup.timeIntervalSince(Date())
            guard toSleep > 0 else { continue }
            // +1ms cushion so the next loop iteration sees the stamp as
            // strictly expired (avoids tight thrash on clock granularity).
            try? await Task.sleep(nanoseconds: UInt64(toSleep * 1_000_000_000) + 1_000_000)
        }

        // Stamp after any sleep completed so `durationFromIssued` (used by
        // network-log diagnostics) tracks the moment the request actually
        // left the gate, not when it was queued.
        let stamp = Date()
        lastRequest = stamp
        recentGrants.append(stamp)
    }
}

/// URLSession wrapper: User-Agent, optional Bearer, light rate limit (~5 rps).
final class ShikimoriHTTPClient: ShikimoriHTTPClientProtocol, Sendable {
    private let configuration: ShikimoriConfiguration
    private let session: URLSession
    private let throttler: RequestThrottler

    init(
        configuration: ShikimoriConfiguration,
        session: URLSession = .shared,
        throttler: RequestThrottler = .shared
    ) {
        self.configuration = configuration
        self.session = session
        self.throttler = throttler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        await throttler.waitTurn()
        var req = request
        req.setValue(configuration.userAgentHeaderValue, forHTTPHeaderField: "User-Agent")
        if let token = configuration.accessToken, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let startedAt = Date()
        do {
            let (data, response) = try await session.data(for: req)
            let http = response as? HTTPURLResponse
            // `log` is nonisolated and self-gates on `isEnabled` — when
            // diagnostics are off (the common case) this is a function call
            // away from a no-op. No MainActor hop on the hot path.
            NetworkLogStore.shared.log(
                method: req.httpMethod ?? "GET",
                url: req.url,
                statusCode: http?.statusCode,
                duration: Date().timeIntervalSince(startedAt),
                responseBytes: data.count,
                responsePreview: NetworkLogStore.previewFromResponseData(data, maxBytes: 1024),
                errorDescription: nil
            )
            // A live 401 means the access token went stale mid-session.
            // `ShikimoriAuthController` listens and tries a token refresh before
            // surfacing re-auth. OAuth `/oauth/token` calls use their own
            // session and never reach this client, so a failed refresh can't
            // re-trigger this — no recursion.
            if http?.statusCode == 401 {
                NotificationCenter.default.post(name: .shikimoriUnauthorized, object: nil)
            }
            return (data, response)
        } catch {
            NetworkLogStore.shared.log(
                method: req.httpMethod ?? "GET",
                url: req.url,
                statusCode: nil,
                duration: Date().timeIntervalSince(startedAt),
                responseBytes: nil,
                responsePreview: nil,
                errorDescription: error.localizedDescription
            )
            throw error
        }
    }

    func jsonRequest(
        url: URL,
        method: String = "GET",
        jsonBody: Data? = nil,
        contentType: String? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let jsonBody {
            req.httpBody = jsonBody
            req.setValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ShikimoriAPIError.invalidResponse }
        return (data, http)
    }

    func formRequest(url: URL, method: String, formFields: [String: String]) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        var c = URLComponents()
        c.queryItems = formFields.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = Data((c.percentEncodedQuery ?? "").utf8)
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await data(for: req)
        guard let http = response as? HTTPURLResponse else { throw ShikimoriAPIError.invalidResponse }
        return (data, http)
    }

    /// Throws `.httpStatus` for any non-2xx response and returns the body
    /// untouched on success. Replaces six identical guards previously
    /// inlined across `ShikimoriGraphQLClient` — one place to add tracing,
    /// custom error mapping, etc.
    static func throwIfNotOK(response: HTTPURLResponse, body: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw ShikimoriAPIError.httpStatus(
                code: response.statusCode,
                body: body.isEmpty ? nil : body
            )
        }
    }
}

extension Notification.Name {
    /// Posted by `ShikimoriHTTPClient` on any 401 from the Shikimori API.
    /// `ShikimoriAuthController` observes it to refresh the access token, or
    /// surface re-auth if the refresh token is itself rejected/missing.
    static let shikimoriUnauthorized = Notification.Name("shikimoriUnauthorized")
}
