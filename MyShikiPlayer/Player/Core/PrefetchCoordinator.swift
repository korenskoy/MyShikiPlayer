//
//  PrefetchCoordinator.swift
//  MyShikiPlayer
//
//  Background pre-resolve of the next episode's streams. Once the user
//  has watched `triggerRatio` of the current episode, we kick off a
//  resolve of N+1 so a tap on it (or auto-advance) is instant.
//
//  Owns its own Task / cancellation / per-episode dedup. PlaybackSession
//  hands it everything it needs through `prepareForNewTitle` /
//  `evaluateTick` and consumes prefetched streams via `take(forEpisode:)`.
//
//  Phase 4 split. Behaviour preserved 1:1 — the original logic moved
//  here, the facade only wires it up.
//

import Foundation

@MainActor
final class PrefetchCoordinator {
    struct PrefetchedEpisode {
        let sources: [PlaybackSession.MediaSource]
        let studios: [StudioOption]
    }

    private let sourceRegistry: SourceRegistry
    private let diagnostics: PlayerDiagnostics
    /// Watched-ratio after which prefetch of N+1 kicks in.
    private let triggerRatio: Double

    /// Ready `MediaSource`s for episodes resolved ahead of time.
    /// Key is the episode number. When the user actually switches
    /// to that episode, `take(forEpisode:)` removes & returns the entry.
    private var prefetchedSources: [Int: PrefetchedEpisode] = [:]
    /// Episode for which prefetch already started (or finished) — so the
    /// timer observer does not spawn parallel tasks on every tick.
    private var prefetchTriggeredForEpisode: Int?
    private var prefetchTask: Task<Void, Never>?

    init(
        sourceRegistry: SourceRegistry,
        diagnostics: PlayerDiagnostics,
        triggerRatio: Double = 0.7
    ) {
        self.sourceRegistry = sourceRegistry
        self.diagnostics = diagnostics
        self.triggerRatio = triggerRatio
    }

    // MARK: - Lifecycle

    /// Reset everything when the user opens a different title — old prefetches
    /// belong to a different shikimoriId and would never be consumed.
    func resetForNewTitle() {
        prefetchedSources.removeAll()
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchTriggeredForEpisode = nil
    }

    /// Called from `prepare` — the next episode starts fresh, so the
    /// trigger flag for the previous one no longer applies.
    func resetTriggerFlag() {
        prefetchTriggeredForEpisode = nil
    }

    /// Pull the prefetched entry for the episode (if any) and remove it from
    /// the cache. Returns nil if nothing was prefetched.
    func take(forEpisode episode: Int) -> PrefetchedEpisode? {
        prefetchedSources.removeValue(forKey: episode)
    }

    // MARK: - Trigger

    /// Inspect the current playback position and, if past `triggerRatio` of
    /// the running episode, kick off background prefetch of N+1.
    func evaluateTick(
        currentShikimoriId: Int?,
        currentEpisode: Int,
        position: Double,
        duration: Double,
        availableEpisodes: [Int],
        title: String,
        preferredTranslationId: Int?
    ) {
        guard prefetchTriggeredForEpisode != currentEpisode else { return }
        guard let shikimoriId = currentShikimoriId else { return }
        guard duration > 0 else { return }
        guard position / duration >= triggerRatio else { return }
        let nextEpisode = currentEpisode + 1
        // Skip prefetch if the episode is not present in the catalog at all.
        if !availableEpisodes.isEmpty, !availableEpisodes.contains(nextEpisode) { return }
        prefetchTriggeredForEpisode = currentEpisode
        prefetchTask?.cancel()
        prefetchTask = Task { [weak self] in
            await self?.prefetchEpisode(
                nextEpisode,
                shikimoriId: shikimoriId,
                title: title,
                preferredTranslationId: preferredTranslationId
            )
        }
    }

    // MARK: - Internal

    func prefetchEpisode(
        _ episode: Int,
        shikimoriId: Int,
        title: String,
        preferredTranslationId: Int?
    ) async {
        if prefetchedSources[episode] != nil { return }
        let request = SourceResolutionRequest(
            shikimoriId: shikimoriId,
            episode: episode,
            preferredTranslationId: preferredTranslationId
        )
        NetworkLogStore.shared.logUIEvent("watch_prefetch_start episode=\(episode)")
        var loaded: [PlaybackSession.MediaSource] = []
        var studios: [StudioOption] = []
        let chain = sourceRegistry.availableProviders.compactMap { sourceRegistry.adapters[$0] }
        if let primary = chain.first {
            let fallbacks = Array(chain.dropFirst())
            do {
                let outcome = try await sourceRegistry.resolveWithFallback(
                    request: request,
                    primary: primary,
                    fallbacks: fallbacks
                )
                for stream in outcome.result.streams {
                    loaded.append(
                        PlaybackSession.MediaSource(
                            provider: outcome.usedAdapter.provider,
                            streamURL: stream.url,
                            qualityLabel: stream.qualityLabel,
                            studioLabel: stream.studioLabel,
                            studioId: stream.studioId,
                            openingRangeSeconds: stream.openingRangeSeconds,
                            episode: episode,
                            title: title
                        )
                    )
                }
                for studio in outcome.result.studios where !studios.contains(studio) {
                    studios.append(studio)
                }
            } catch {
                // Best-effort: prefetch errors do not propagate to lastError;
                // the user will see the real error when manually opening the
                // episode. No fallback hint is shown for prefetch — the user
                // did not trigger this resolve, so a banner would feel out of context.
                diagnostics.log("prefetch chain ep=\(episode) failed: \(error.localizedDescription)")
            }
        }
        if Task.isCancelled { return }
        guard !loaded.isEmpty else {
            NetworkLogStore.shared.logUIEvent("watch_prefetch_empty episode=\(episode)")
            return
        }
        prefetchedSources[episode] = PrefetchedEpisode(sources: loaded, studios: studios)
        NetworkLogStore.shared.logUIEvent(
            "watch_prefetch_done episode=\(episode) sources=\(loaded.count) studios=\(studios.count)"
        )
    }
}
