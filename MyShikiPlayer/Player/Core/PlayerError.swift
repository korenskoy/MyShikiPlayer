//
//  PlayerError.swift
//  MyShikiPlayer
//

import Foundation

enum PlayerError: LocalizedError {
    case noStreamFound
    case streamBuildFailed(String)
    case sourceUnavailable(String)
    /// Provider replied 401 / 403 — credentials look stale. The UI surfaces a
    /// "re-login / check token" hint; the player itself MUST NOT clear any
    /// stored token (see feedback_player_resilience).
    case providerAuthFailed(String)
    /// Provider explicitly refused the resource (HTTP 451 / blocked content).
    /// Retrying is pointless — the user should be told the source itself is
    /// unavailable for this title.
    case providerBlocked(String)
    /// 429 / 5xx — generic transient failure that the user (or upstream
    /// retry policy) can attempt again.
    case providerTransient(provider: String, status: Int)

    var errorDescription: String? {
        // Mirror logic for fallback eligibility lives in the
        // `RetryableSourceError` extension at the bottom of this file —
        // keep both sections in sync when adding a new case.
        switch self {
        case .noStreamFound:
            return "Не найден доступный поток для воспроизведения."
        case .streamBuildFailed(let reason):
            return "Не удалось подготовить поток: \(reason)"
        case .sourceUnavailable(let source):
            return "Источник \(source) сейчас недоступен."
        case .providerAuthFailed(let source):
            return "Требуется повторный вход / проверьте токен \(source)."
        case .providerBlocked(let source):
            return "Источник \(source) недоступен (блокировка поставщика)."
        case .providerTransient(let provider, let status):
            return "Временная ошибка источника \(provider) (HTTP \(status)). Повторите попытку."
        }
    }
}

/// Lets `SourceRegistry.resolveWithFallback` decide whether a
/// `PlayerError` thrown by an adapter is worth retrying through the next one.
/// Auth/blocked/transient/sourceUnavailable failures all describe a
/// provider-side problem — switching providers may serve the same title.
/// `noStreamFound` and `streamBuildFailed` describe local outcomes (the
/// catalog had nothing for this title, or the resolver failed to parse) and
/// the next adapter cannot heal them.
extension PlayerError: RetryableSourceError {
    var isRetryableViaFallback: Bool {
        switch self {
        case .providerAuthFailed, .providerBlocked, .providerTransient, .sourceUnavailable:
            return true
        case .noStreamFound, .streamBuildFailed:
            return false
        }
    }
}
