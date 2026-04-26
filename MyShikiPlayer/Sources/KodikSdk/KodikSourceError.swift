//
//  KodikSourceError.swift
//  MyShikiPlayer
//

import Foundation

/// Provider-agnostic protocol that lets `SourceRegistry.resolveWithFallback`
/// decide whether a thrown error is worth retrying through the next adapter.
/// New providers should expose their own error type and conform — keeping the
/// fallback policy in one place rather than scattered switch-statements.
///
/// - `auth` / `banned` / `transient` style failures are upstream-side and a
///   different provider may serve the same title without issue → return `true`.
/// - `parse` / `network` style failures are local (broken decoder, no Wi-Fi)
///   and switching adapters will not help → return `false`.
public protocol RetryableSourceError {
    var isRetryableViaFallback: Bool { get }
}

/// Domain-level Kodik failure categories. Kept separate from `PlayerError` so
/// the SDK layer can stay UI-agnostic; `KodikAdapter` is responsible for the
/// final mapping into `PlayerError` consumed by `PlaybackSession`.
public enum KodikSourceError: Error, LocalizedError {
    /// 401 / 403 — the API token must be re-checked or the user must re-login.
    /// MUST NOT trigger a token reset (see feedback_player_resilience).
    case auth
    /// 451 / `blocked_seasons: "all"` — the resource or content is blocked
    /// by the provider; retrying is pointless.
    case banned
    /// 429 / 5xx — transient server-side condition, safe to retry.
    case transient(status: Int)
    /// Response received but could not be decoded into the expected schema.
    case parse(String)
    /// Transport-layer failure (URLError, TLS, etc.).
    case network(Error)

    public var errorDescription: String? {
        switch self {
        case .auth:
            return "Нужно проверить токен Kodik в настройках."
        case .banned:
            return "Контент заблокирован поставщиком."
        case .transient(let status):
            return "Временная ошибка Kodik (HTTP \(status)). Повторите попытку."
        case .parse(let message):
            return "Не удалось разобрать ответ Kodik: \(message)"
        case .network(let error):
            return "Сетевая ошибка Kodik: \(error.localizedDescription)"
        }
    }

    /// Helper: classify an HTTP status code into the matching `KodikSourceError`
    /// case, or return nil for 2xx responses.
    public static func classify(httpStatus status: Int) -> KodikSourceError? {
        switch status {
        case 200..<300:
            return nil
        case 401, 403:
            return .auth
        case 451:
            return .banned
        case 429, 500..<600:
            return .transient(status: status)
        default:
            // Treat other 4xx as transient with status preserved — UI will
            // surface "временная ошибка" rather than a misleading "auth" /
            // "banned" wording.
            return .transient(status: status)
        }
    }
}

// MARK: - Fallback policy

/// `parse`/`network` are local issues — bypass the fallback chain so the
/// user sees the real cause instead of a misleading "trying next source" loop.
extension KodikSourceError: RetryableSourceError {
    public var isRetryableViaFallback: Bool {
        switch self {
        case .auth, .banned, .transient:
            return true
        case .parse, .network:
            return false
        }
    }
}
