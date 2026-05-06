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
    private var lastRequest: Date = .distantPast
    private let minInterval: TimeInterval

    init(minInterval: TimeInterval = 0.2) {
        self.minInterval = minInterval
    }

    func waitTurn() async {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastRequest)
        if elapsed < minInterval {
            let ns = UInt64((minInterval - elapsed) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
        }
        // Stamp after any sleep completed so `durationFromIssued` (used by
        // network-log diagnostics) tracks the moment the request actually
        // left the gate, not when it was queued.
        lastRequest = Date()
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
        minRequestInterval: TimeInterval = 0.2
    ) {
        self.configuration = configuration
        self.session = session
        self.throttler = RequestThrottler(minInterval: minRequestInterval)
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
