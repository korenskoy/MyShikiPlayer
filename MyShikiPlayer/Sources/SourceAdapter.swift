//
//  SourceAdapter.swift
//  MyShikiPlayer
//

import Foundation

enum SourceProvider: String, CaseIterable {
    case kodik
    case aniliberty
    case anilibria
    case anime365
    case anilib
}

struct SourceStream: Hashable {
    /// Pure quality label: "720p", "480p", "HD".
    let qualityLabel: String
    /// Dub studio (Kodik translation.title etc.). Nil if the source does not provide one.
    let studioLabel: String?
    /// Studio/dub identifier on the source side (Kodik translation.id etc.).
    /// Needed so the user can pin the studio choice across episodes.
    let studioId: Int?
    let url: URL
    let openingRangeSeconds: ClosedRange<Double>?
    let endingRangeSeconds: ClosedRange<Double>?
}

/// Studio entry shown in the player's DUB picker. Lives independently of
/// `SourceStream` because we resolve studios lazily — the picker must list
/// every option from the catalog while only the user-picked one has streams
/// behind it.
struct StudioOption: Hashable {
    let provider: SourceProvider
    let studioId: Int
    let studioLabel: String
}

struct SourceResolutionResult {
    /// Streams the adapter resolved eagerly (for the requested
    /// `preferredTranslationId`, or the first available studio when no
    /// preference is provided).
    let streams: [SourceStream]
    /// Studios known to the catalog but whose streams were not resolved yet.
    /// The player surfaces them in the DUB picker and asks the adapter to
    /// resolve a specific one via `SourceAdapter.resolveStudio` only when
    /// the user picks it.
    let studios: [StudioOption]

    init(streams: [SourceStream], studios: [StudioOption] = []) {
        self.streams = streams
        self.studios = studios
    }
}

struct SourceResolutionRequest {
    let shikimoriId: Int
    let episode: Int
    let preferredTranslationId: Int?
}

protocol SourceAdapter {
    var provider: SourceProvider { get }
    func resolve(request: SourceResolutionRequest) async throws -> SourceResolutionResult
    /// On-demand resolution of a single studio that was previously surfaced
    /// in `SourceResolutionResult.studios`. Default implementation throws
    /// `PlayerError.sourceUnavailable` so adapters that do not support the
    /// lazy DUB picker (stubs, single-studio providers) keep compiling.
    func resolveStudio(
        request: SourceResolutionRequest,
        studioId: Int
    ) async throws -> [SourceStream]
}

extension SourceAdapter {
    func resolveStudio(
        request: SourceResolutionRequest,
        studioId: Int
    ) async throws -> [SourceStream] {
        throw PlayerError.sourceUnavailable("\(provider.rawValue) (no per-studio resolution)")
    }
}

/// Outcome of `SourceRegistry.resolveWithFallback`. `fallbacksTried` is empty
/// when the primary adapter served the request directly; otherwise it lists
/// every adapter the registry attempted before the one that finally succeeded
/// (including the `error` it failed with). The UI layer can read it to show a
/// short "playing via backup source" hint.
struct FallbackOutcome {
    let result: SourceResolutionResult
    let usedAdapter: SourceAdapter
    let fallbacksTried: [(adapter: SourceAdapter, error: Error)]
}

struct SourceRegistry {
    let adapters: [SourceProvider: SourceAdapter]

    /// Live registry. Only providers with a working implementation are listed
    /// here; the Aniliberty / Anilibria / Anime365 / Anilib stubs in
    /// `MyShikiPlayer/Sources/` exist as scaffolding for future work but are
    /// intentionally not registered, to avoid spamming `sourceUnavailable`
    /// errors on every Play tap.
    static let live = SourceRegistry(
        adapters: [
            .kodik: KodikAdapter()
        ]
    )

    /// Providers that have a registered adapter. Use this instead of
    /// `SourceProvider.allCases` when iterating sources to play.
    var availableProviders: [SourceProvider] {
        SourceProvider.allCases.filter { adapters[$0] != nil }
    }

    func resolve(provider: SourceProvider, request: SourceResolutionRequest) async throws -> SourceResolutionResult {
        guard let adapter = adapters[provider] else {
            throw PlayerError.sourceUnavailable(provider.rawValue)
        }
        return try await adapter.resolve(request: request)
    }

    func resolveStudio(
        provider: SourceProvider,
        request: SourceResolutionRequest,
        studioId: Int
    ) async throws -> [SourceStream] {
        guard let adapter = adapters[provider] else {
            throw PlayerError.sourceUnavailable(provider.rawValue)
        }
        return try await adapter.resolveStudio(request: request, studioId: studioId)
    }

    /// Try `primary` first; on a fallback-eligible failure (per
    /// `RetryableSourceError`), walk through `fallbacks` in order until either
    /// one succeeds or the wall-clock `budget` is exhausted.
    ///
    /// On total failure the **first** significant error is rethrown — that
    /// one is the most informative for the UI ("Kodik is down" beats "the
    /// stub backup said sourceUnavailable"), and the remaining attempts are
    /// kept inside `FallbackOutcome.fallbacksTried` for diagnostics anyway.
    ///
    /// `parse` / `network` style errors short-circuit immediately: the next
    /// adapter cannot heal a broken JSON decoder or a dead Wi-Fi link.
    ///
    /// Today only Kodik is registered, so callers usually pass `fallbacks: []`
    /// and behaviour is identical to a plain `adapter.resolve(...)`. Adding
    /// a real second adapter is a one-liner at the call-site.
    func resolveWithFallback(
        request: SourceResolutionRequest,
        primary: SourceAdapter,
        fallbacks: [SourceAdapter] = [],
        budget: TimeInterval = 12.0
    ) async throws -> FallbackOutcome {
        let started = Date()
        var firstSignificantError: Error?
        var tried: [(adapter: SourceAdapter, error: Error)] = []

        let chain: [SourceAdapter] = [primary] + fallbacks
        for (index, adapter) in chain.enumerated() {
            // Wall-clock guard: do not start another adapter once the budget
            // is gone. The primary attempt always runs (the user explicitly
            // asked for it) — only the fallbacks are gated.
            if index > 0, Date().timeIntervalSince(started) >= budget {
                await Self.log(
                    "fallback_budget_exhausted budget=\(budget)s tried=\(tried.count)"
                )
                break
            }
            do {
                let result = try await adapter.resolve(request: request)
                if index > 0 {
                    await Self.log(
                        "fallback_success used=\(adapter.provider.rawValue) tried=\(tried.count)"
                    )
                }
                return FallbackOutcome(
                    result: result,
                    usedAdapter: adapter,
                    fallbacksTried: tried
                )
            } catch {
                if firstSignificantError == nil { firstSignificantError = error }
                tried.append((adapter: adapter, error: error))
                await Self.log(
                    "fallback_attempt_fail provider=\(adapter.provider.rawValue)"
                    + " err=\(error.localizedDescription)"
                )
                // Local / non-recoverable failures: swapping providers will
                // not help, so surface the real error immediately.
                if let typed = error as? RetryableSourceError, !typed.isRetryableViaFallback {
                    throw error
                }
                // Untyped errors (e.g. PlayerError.sourceUnavailable from an
                // unimplemented stub adapter) are treated as retry-eligible —
                // there is nothing else to be lost by trying the next one.
            }
        }

        if let firstSignificantError {
            throw firstSignificantError
        }
        throw PlayerError.sourceUnavailable(primary.provider.rawValue)
    }

    /// MainActor-hopping log helper — mirrors `KodikAdapter.log(...)` so the
    /// fallback chain plays nicely with strict-concurrency regardless of the
    /// caller's actor isolation.
    private static func log(_ message: String) async {
        await MainActor.run {
            NetworkLogStore.shared.logUIEvent("fallback \(message)")
        }
    }
}
