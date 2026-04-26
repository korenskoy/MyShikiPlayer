//
//  RetryPolicy.swift
//  MyShikiPlayer
//

import Foundation

/// Backoff helper for Shikimori-bound network calls. Centralises the 429 retry
/// schedule that used to be copy-pasted across repositories.
enum RetryPolicy {
    /// Default backoff for Shikimori HTTP 429 (immediate, 0.5s, 1.5s).
    static let defaultBackoff: [UInt64] = [0, 500_000_000, 1_500_000_000]

    /// Exponential backoff with jitter, used by call-sites that previously
    /// rolled their own retry loop (Library list / chunked GraphQL fetches).
    /// Three attempts: 0s, ~0.5s, ~1.0s — same shape as the old hand-written
    /// loop, just in one place.
    static let exponentialBackoff: [UInt64] = [
        0,
        500_000_000,
        1_000_000_000
    ]

    /// True if the error is a Shikimori HTTP 429 rate-limit response.
    static func isRateLimited(_ error: Error) -> Bool {
        guard let api = error as? ShikimoriAPIError else { return false }
        if case .httpStatus(let code, _) = api, code == 429 { return true }
        return false
    }

    /// Broader transient predicate covering 429, 5xx, common network drops and
    /// the Cloudflare-flavoured 522. Used by callers that want the wider net
    /// without losing the central retry scheduling.
    static func isTransient(_ error: Error) -> Bool {
        if let api = error as? ShikimoriAPIError {
            if case .httpStatus(let code, _) = api {
                return code == 429 || code == 522 || code >= 500
            }
            return false
        }
        if let url = error as? URLError {
            switch url.code {
            case .timedOut,
                 .cannotConnectToHost,
                 .networkConnectionLost,
                 .notConnectedToInternet,
                 .dnsLookupFailed,
                 .resourceUnavailable:
                return true
            default:
                return false
            }
        }
        return false
    }

    /// Runs `operation` with backoff, retrying only on rate-limit (429) errors.
    /// - Parameters:
    ///   - delays: Per-attempt sleep durations (nanoseconds). Length defines the max attempt count.
    ///   - shouldRetry: Predicate deciding whether a thrown error is retryable. Defaults to 429-only.
    ///   - onRetry: Called for every retryable error caught with the failed attempt index and whether another retry will follow.
    /// - Returns: The first successful value.
    /// - Throws: The original error if it is not retryable, or the last one once retries are exhausted.
    static func withRateLimitRetry<T>(
        delays: [UInt64] = defaultBackoff,
        shouldRetry: (Error) -> Bool = RetryPolicy.isRateLimited,
        onRetry: (Int, Bool) async -> Void = { _, _ in },
        _ operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for (attempt, delay) in delays.enumerated() {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            do {
                return try await operation()
            } catch {
                lastError = error
                if !shouldRetry(error) { throw error }
                await onRetry(attempt, attempt < delays.count - 1)
            }
        }
        throw lastError ?? ShikimoriAPIError.httpStatus(code: 429, body: nil)
    }
}
