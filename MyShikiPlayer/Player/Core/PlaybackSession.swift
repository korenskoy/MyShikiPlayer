//
//  PlaybackSession.swift
//  MyShikiPlayer
//
//  Facade for one playback "session": current title + episode, the engine,
//  and the selected source. Heavy lifting is delegated to coordinators:
//
//  - PrefetchCoordinator     — background pre-resolve of N+1.
//  - ResumeCoordinator       — WatchProgressStore + WatchHistoryStore I/O.
//  - StreamSelector          — pure helpers for picking among MediaSources.
//
//  Public API (`prepare`, `selectEpisodeAndLoad`, `selectStudioAndLoad`,
//  `saveProgressSnapshot`, etc.) and every `@Published` field stay
//  identical — Views must not rebuild because of this refactor
//  (feedback_ui_stability).
//

import Foundation
import Combine

@MainActor
final class PlaybackSession: ObservableObject {
    struct MediaSource: Identifiable, Hashable {
        let id = UUID()
        let provider: SourceProvider
        let streamURL: URL
        /// Pure quality: "720p", "480p". No studio prefixes.
        let qualityLabel: String
        /// Dub studio name (if the source provides it). Used as the DUB label.
        let studioLabel: String?
        /// Studio identifier on the source side (Kodik translation.id, etc.).
        let studioId: Int?
        let openingRangeSeconds: ClosedRange<Double>?
        let endingRangeSeconds: ClosedRange<Double>?
        let episode: Int
        let title: String
    }

    @Published private(set) var availableSources: [MediaSource] = []
    @Published private(set) var selectedSource: MediaSource?
    @Published private(set) var lastError: PlayerError?
    @Published var isPreparing = false
    /// Short notice shown when playback fell back from the primary source to
    /// a backup adapter. Auto-clears after `fallbackHintAutoDismissSeconds`.
    /// Read by the player overlay; never set from a SwiftUI body
    /// (see feedback_no_side_effects_in_body).
    @Published private(set) var fallbackHint: String?
    /// Studios known for the current episode. The DUB picker reads this list,
    /// not `availableSources`, because most studios are resolved lazily — the
    /// catalog already knows their labels even before any stream URL exists.
    @Published private(set) var availableStudios: [StudioOption] = []
    /// Studio currently being resolved on demand (after the user picked it
    /// in the DUB picker). Lets the UI show a spinner / disable repeats
    /// until the streams arrive.
    @Published private(set) var resolvingStudioId: Int?
    /// Full list of episodes for the title, propagated from Details. An empty array
    /// means the data is not loaded yet (UI should provide its own fallback).
    @Published private(set) var availableEpisodes: [Int] = []

    let engine = PlayerEngine()
    let diagnostics = PlayerDiagnostics()
    /// Exposed for callers that read the persisted resume position directly
    /// (kept for source compatibility with pre-Phase-4 code).
    var progressStore: WatchProgressStore { resumeCoordinator.progressStore }

    private let sourceRegistry: SourceRegistry
    private let resumeCoordinator: ResumeCoordinator
    private let prefetchCoordinator: PrefetchCoordinator
    private var cancellables: Set<AnyCancellable> = []
    private var loadRetryCount = 0
    private let maxLoadRetries = 2
    /// How long the fallback banner stays visible before fading out.
    /// 3.5s matches the UI rule of brief, calm hints (feedback_ui_stability).
    private let fallbackHintAutoDismissSeconds: UInt64 = 3_500_000_000
    private var fallbackHintDismissTask: Task<Void, Never>?
    private(set) var currentShikimoriId: Int?
    private(set) var currentEpisode: Int = 1
    private(set) var preferredTranslationId: Int?

    /// Called before loading another episode: leaving episode, position and duration for progress sync.
    var onBeforeEpisodeChange: ((_ leavingEpisode: Int, _ position: Double, _ duration: Double) -> Void)?

    /// Called when an episode is considered "watched" (progress >= `watchedThreshold`)
    /// — exactly once per viewing session of that episode. The receiver is
    /// responsible for reporting it to Shikimori (PATCH user_rate.episodes).
    var onEpisodeWatched: ((_ episode: Int) -> Void)?

    /// Watched ratio after which an episode is considered "watched". 0.85 is the
    /// standard (skips ending + credits). Tunable by tests / future UI.
    var watchedThreshold: Double = 0.85

    /// Idempotency — which episodes were already reported during this session.
    /// Reset by `prepare()` (new title / fresh load).
    private var reportedWatchedEpisodes: Set<Int> = []

    /// (Episode, range kind) pairs for which auto-skip already fired in this
    /// session. Prevents the user from being "trapped" if they manually rewind
    /// back into an opening they already skipped past. Cleared on episode /
    /// source switches via `resetAutoSkipFlags()`.
    private var firedAutoSkips: Set<AutoSkipKey> = []
    private struct AutoSkipKey: Hashable {
        let episode: Int
        let kind: PlayerSegmentKind
    }
    /// Cached mirror of `UserDefaults[SettingsKeys.autoSkipChapters]`. Refreshed
    /// only when UserDefaults actually changes — the auto-skip tick runs ~4x
    /// per second and reading the default each time is wasteful even though
    /// the values are in-process cached.
    private var autoSkipEnabled: Bool = UserDefaults.standard.bool(
        forKey: SettingsKeys.autoSkipChapters
    )

    init(sourceRegistry: SourceRegistry = .live, progressStore: WatchProgressStore? = nil) {
        self.sourceRegistry = sourceRegistry
        self.resumeCoordinator = ResumeCoordinator(progressStore: progressStore ?? WatchProgressStore())
        self.prefetchCoordinator = PrefetchCoordinator(
            sourceRegistry: sourceRegistry,
            diagnostics: diagnostics
        )
        engine.$lastLoadError
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.handleEngineLoadFailure(error)
            }
            .store(in: &cancellables)
        engine.$currentTime
            .sink { [weak self] _ in
                self?.maybeTriggerPrefetch()
                self?.maybeAutoSkipSection()
            }
            .store(in: &cancellables)
        // Refresh the cached toggle only when UserDefaults actually changes.
        // didChangeNotification fires for any key in the suite — that is fine,
        // it still happens orders of magnitude less often than the playback tick.
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            .sink { [weak self] _ in
                self?.autoSkipEnabled = UserDefaults.standard.bool(
                    forKey: SettingsKeys.autoSkipChapters
                )
            }
            .store(in: &cancellables)
    }

    /// Updates the pinned dub studio. The next episode preparation will put the
    /// stream from that studio first.
    func updatePreferredTranslationId(_ id: Int?) {
        preferredTranslationId = id
        NetworkLogStore.shared.logUIEvent(
            "watch_preferred_translation_updated id=\(id.map(String.init) ?? "nil")"
        )
    }

    func prepare(
        shikimoriId: Int,
        title: String,
        episode: Int = 1,
        preferredTranslationId: Int? = nil,
        availableEpisodes: [Int]? = nil
    ) async {
        isPreparing = true
        lastError = nil
        if currentShikimoriId != shikimoriId {
            reportedWatchedEpisodes.removeAll()
            prefetchCoordinator.resetForNewTitle()
        }
        prefetchCoordinator.resetTriggerFlag()
        resetAutoSkipFlags()
        currentShikimoriId = shikimoriId
        currentEpisode = episode
        self.preferredTranslationId = preferredTranslationId
        // Only update the episode list when it was passed — selectEpisodeAndLoad
        // calls prepare without this parameter and must not wipe known data.
        if let availableEpisodes {
            self.availableEpisodes = availableEpisodes
        }
        NetworkLogStore.shared.logUIEvent(
            "watch_prepare_start shikimori_id=\(shikimoriId) episode=\(episode) preferred_translation=\(preferredTranslationId.map(String.init) ?? "nil")"
        )
        defer { isPreparing = false }

        let request = SourceResolutionRequest(
            shikimoriId: shikimoriId,
            episode: episode,
            preferredTranslationId: preferredTranslationId
        )
        let outcome = await resolveOrTakePrefetched(
            request: request,
            episode: episode,
            title: title
        )
        let loaded = outcome.sources
        let firstProviderError = outcome.firstError

        availableSources = loaded
        availableStudios = outcome.studios
        NetworkLogStore.shared.logUIEvent(
            "watch_prepare_sources_ready count=\(loaded.count) qualities=[\(loaded.map(\.qualityLabel).joined(separator: ","))]"
        )
        let previousSelection = selectedSource
        guard let first = loaded.first else {
            selectedSource = nil
            NetworkLogStore.shared.logUIEvent("watch_prepare_no_sources")
            if let providerError = firstProviderError as? PlayerError {
                lastError = providerError
            } else {
                lastError = .noStreamFound
            }
            return
        }
        if let previousSelection,
           let matching = loaded.first(where: { $0.streamURL == previousSelection.streamURL }) {
            select(source: matching, autoLoadPlayerItem: false)
            NetworkLogStore.shared.logUIEvent("watch_prepare_selected restored quality=\(matching.qualityLabel)")
        } else {
            select(source: first, autoLoadPlayerItem: false)
            NetworkLogStore.shared.logUIEvent("watch_prepare_selected first quality=\(first.qualityLabel)")
        }
        resumeCoordinator.recordStarted(
            shikimoriId: shikimoriId,
            episode: episode,
            title: title
        )
    }

    func select(source: MediaSource, autoLoadPlayerItem: Bool = false) {
        // A new source may carry different opening/ending ranges (different
        // studio, different quality). Drop the per-episode auto-skip flags so
        // the new ranges get a fresh chance to fire.
        if selectedSource?.streamURL != source.streamURL {
            resetAutoSkipFlags()
        }
        selectedSource = source
        diagnostics.log("selected \(source.provider.rawValue) \(source.qualityLabel)")
        if autoLoadPlayerItem {
            loadSelectedSource(autoPlay: false)
        }
    }

    func loadSelectedSource(autoPlay: Bool) {
        guard let source = selectedSource else { return }
        loadRetryCount = 0
        lastError = nil
        engine.load(url: source.streamURL, autoPlay: autoPlay)
        // Resume: if the last saved position for the title belongs to this same
        // episode — continue from it. The seek is queued in pendingSeekSeconds
        // inside the engine and applied automatically after readyToPlay.
        if let id = currentShikimoriId,
           let seconds = resumeCoordinator.resumeSeconds(shikimoriId: id, episode: currentEpisode),
           seconds > 1 {
            engine.seek(seconds: seconds)
            NetworkLogStore.shared.logUIEvent(
                "watch_resume shikimori_id=\(id) episode=\(currentEpisode) seconds=\(Int(seconds))"
            )
        }
        diagnostics.log("loaded \(source.provider.rawValue) \(source.qualityLabel)")
    }

    func selectNextSourceAndLoad() {
        guard let current = selectedSource,
              let idx = availableSources.firstIndex(of: current),
              idx + 1 < availableSources.count else { return }
        let next = availableSources[idx + 1]
        select(source: next, autoLoadPlayerItem: false)
        engine.load(url: next.streamURL, autoPlay: true)
        diagnostics.log("fallback next source \(next.provider.rawValue) \(next.qualityLabel)")
    }

    func retryCurrentSource() {
        guard let current = selectedSource else { return }
        engine.load(url: current.streamURL, autoPlay: true)
        diagnostics.log("retry current source \(current.provider.rawValue) \(current.qualityLabel)")
    }

    func selectPreviousEpisodeAndLoad() async {
        guard currentEpisode > 1 else { return }
        let targetEpisode = currentEpisode - 1
        await selectEpisodeAndLoad(targetEpisode)
    }

    func selectNextEpisodeAndLoad() async {
        let targetEpisode = currentEpisode + 1
        // Guard against direct calls bypassing canSelectNextEpisode
        // (shortcuts, callbacks): do not try to resolve a non-existent
        // episode — providers would only return noStreamFound anyway.
        if !availableEpisodes.isEmpty, !availableEpisodes.contains(targetEpisode) { return }
        await selectEpisodeAndLoad(targetEpisode)
    }

    @discardableResult
    func ensureSelectedSource() -> Bool {
        if let selectedSource,
           availableSources.contains(where: { $0.streamURL == selectedSource.streamURL }) {
            NetworkLogStore.shared.logUIEvent("watch_ensure_selected keep quality=\(selectedSource.qualityLabel)")
            return true
        }
        guard let first = availableSources.first else { return false }
        select(source: first, autoLoadPlayerItem: false)
        NetworkLogStore.shared.logUIEvent("watch_ensure_selected auto quality=\(first.qualityLabel)")
        return true
    }

    private func handleEngineLoadFailure(_ message: String) {
        diagnostics.log("engine load failure: \(message)")
        if loadRetryCount < maxLoadRetries, let current = selectedSource {
            loadRetryCount += 1
            diagnostics.log("retry \(loadRetryCount)/\(maxLoadRetries) for \(current.provider.rawValue) \(current.qualityLabel)")
            engine.load(url: current.streamURL, autoPlay: true)
            return
        }
        if let current = selectedSource,
           let idx = availableSources.firstIndex(of: current),
           idx + 1 < availableSources.count {
            let fallback = availableSources[idx + 1]
            select(source: fallback, autoLoadPlayerItem: false)
            diagnostics.log("switching to fallback \(fallback.provider.rawValue) \(fallback.qualityLabel)")
            loadRetryCount = 0
            engine.load(url: fallback.streamURL, autoPlay: true)
            return
        }
        lastError = .streamBuildFailed(message)
    }

    func saveProgressSnapshot() {
        guard let id = currentShikimoriId else { return }
        resumeCoordinator.recordProgress(
            shikimoriId: id,
            episode: currentEpisode,
            title: selectedSource?.title ?? "",
            position: engine.currentTime,
            duration: engine.duration
        )
        reportWatchedIfSufficient(
            episode: currentEpisode,
            position: engine.currentTime,
            duration: engine.duration
        )
    }

    /// If `position / duration >= watchedThreshold` — calls `onEpisodeWatched(episode)` exactly once.
    /// Invoked both when switching between episodes (from `selectEpisodeAndLoad`) and when closing the player.
    func reportWatchedIfSufficient(episode: Int, position: Double, duration: Double) {
        guard duration > 0, position > 0, episode >= 1 else { return }
        let ratio = position / duration
        guard ratio >= watchedThreshold else { return }
        guard !reportedWatchedEpisodes.contains(episode) else { return }
        reportedWatchedEpisodes.insert(episode)
        NetworkLogStore.shared.logUIEvent(
            "watch_episode_reported episode=\(episode) ratio=\(String(format: "%.2f", ratio))"
        )
        if let id = currentShikimoriId {
            resumeCoordinator.markCompleted(
                shikimoriId: id,
                episode: episode,
                title: selectedSource?.title ?? "",
                position: position,
                duration: duration
            )
        }
        onEpisodeWatched?(episode)
    }

    var currentOpeningRangeSeconds: ClosedRange<Double>? {
        selectedSource?.openingRangeSeconds
    }

    var currentEndingRangeSeconds: ClosedRange<Double>? {
        selectedSource?.endingRangeSeconds
    }

    var canSelectPreviousEpisode: Bool {
        currentEpisode > 1 && currentShikimoriId != nil && !isPreparing
    }

    var canSelectNextEpisode: Bool {
        guard currentShikimoriId != nil, !isPreparing else { return false }
        // If the episode list has not arrived yet — optimistically allow it
        // (like prefetch does). Otherwise strictly check that the next one exists.
        if availableEpisodes.isEmpty { return true }
        return availableEpisodes.contains(currentEpisode + 1)
    }

    func selectEpisodeAndLoad(_ episode: Int) async {
        guard let shikimoriId = currentShikimoriId else { return }
        let normalized = max(1, episode)
        guard normalized != currentEpisode else { return }
        onBeforeEpisodeChange?(currentEpisode, engine.currentTime, engine.duration)
        // Persist the leaving episode's position — without this, resume would
        // only fire on player close, not on manual episode jumps.
        resumeCoordinator.saveResumePoint(
            shikimoriId: shikimoriId,
            episode: currentEpisode,
            position: engine.currentTime
        )
        reportWatchedIfSufficient(
            episode: currentEpisode,
            position: engine.currentTime,
            duration: engine.duration
        )
        let title = selectedSource?.title ?? "Плеер"
        await prepare(
            shikimoriId: shikimoriId,
            title: title,
            episode: normalized,
            preferredTranslationId: preferredTranslationId
        )
        if ensureSelectedSource() {
            loadSelectedSource(autoPlay: true)
        }
    }
}

// MARK: - Source resolution

extension PlaybackSession {
    fileprivate struct ResolutionOutcome {
        let sources: [MediaSource]
        let studios: [StudioOption]
        let firstError: Error?
    }

    fileprivate func resolveOrTakePrefetched(
        request: SourceResolutionRequest,
        episode: Int,
        title: String
    ) async -> ResolutionOutcome {
        // Pre-resolve hit: the episode is already in the prefetch cache —
        // skip network calls. The title is overwritten with the current
        // `title` (the prefetched MediaSource may have been built with an
        // empty title).
        if let prefetched = prefetchCoordinator.take(forEpisode: episode), !prefetched.sources.isEmpty {
            let sources = prefetched.sources.map { source in
                MediaSource(
                    provider: source.provider,
                    streamURL: source.streamURL,
                    qualityLabel: source.qualityLabel,
                    studioLabel: source.studioLabel,
                    studioId: source.studioId,
                    openingRangeSeconds: source.openingRangeSeconds,
                    endingRangeSeconds: source.endingRangeSeconds,
                    episode: source.episode,
                    title: title
                )
            }
            let studios = prefetched.studios.isEmpty ? StreamSelector.studios(from: sources) : prefetched.studios
            NetworkLogStore.shared.logUIEvent(
                "watch_prepare_prefetch_hit episode=\(episode) sources=\(sources.count)"
            )
            return ResolutionOutcome(sources: sources, studios: studios, firstError: nil)
        }
        return await resolveAcrossProviders(request: request, episode: episode, title: title)
    }

    private func resolveAcrossProviders(
        request: SourceResolutionRequest,
        episode: Int,
        title: String
    ) async -> ResolutionOutcome {
        // Build the primary + fallback chain from the provider order baked
        // into `availableProviders`. Today only Kodik is registered, so
        // `fallbacks` is empty and `resolveWithFallback` is effectively a
        // single-adapter call — no behaviour change. Once a real second
        // provider is added to `SourceRegistry.live`, fallback kicks in
        // automatically.
        let chain = sourceRegistry.availableProviders.compactMap { sourceRegistry.adapters[$0] }
        guard let primary = chain.first else {
            return ResolutionOutcome(sources: [], studios: [], firstError: PlayerError.noStreamFound)
        }
        let fallbacks = Array(chain.dropFirst())
        do {
            let outcome = try await sourceRegistry.resolveWithFallback(
                request: request,
                primary: primary,
                fallbacks: fallbacks
            )
            let mapped: [MediaSource] = outcome.result.streams.map { stream in
                MediaSource(
                    provider: outcome.usedAdapter.provider,
                    streamURL: stream.url,
                    qualityLabel: stream.qualityLabel,
                    studioLabel: stream.studioLabel,
                    studioId: stream.studioId,
                    openingRangeSeconds: stream.openingRangeSeconds,
                    endingRangeSeconds: stream.endingRangeSeconds,
                    episode: episode,
                    title: title
                )
            }
            var studios = outcome.result.studios
            if studios.isEmpty {
                studios = StreamSelector.studios(from: mapped)
            }
            // Surface the "playing via backup" hint only when something
            // actually fell back. The empty array is the common path today
            // (Kodik-only deployment) and produces no UI noise.
            if !outcome.fallbacksTried.isEmpty {
                showFallbackHint(usedProvider: outcome.usedAdapter.provider)
            }
            return ResolutionOutcome(sources: mapped, studios: studios, firstError: nil)
        } catch {
            diagnostics.log("source chain failed: \(error.localizedDescription)")
            return ResolutionOutcome(sources: [], studios: [], firstError: error)
        }
    }

    /// Sets the user-facing fallback hint and schedules its dismissal.
    /// Always called from a non-render code path (await flow inside
    /// `prepare`) — never from a SwiftUI body / computed property
    /// (feedback_no_side_effects_in_body).
    private func showFallbackHint(usedProvider: SourceProvider) {
        fallbackHintDismissTask?.cancel()
        let providerName = usedProvider.rawValue.capitalized
        fallbackHint = "Воспроизведение через резервный источник: \(providerName)"
        NetworkLogStore.shared.logUIEvent(
            "fallback_hint_shown provider=\(usedProvider.rawValue)"
        )
        // Task inherits the enclosing @MainActor isolation — no extra hop
        // required. Cancellation flag is checked after sleep to avoid
        // clobbering a fresh hint with a stale dismissal.
        fallbackHintDismissTask = Task { @MainActor [weak self, fallbackHintAutoDismissSeconds] in
            try? await Task.sleep(nanoseconds: fallbackHintAutoDismissSeconds)
            if Task.isCancelled { return }
            self?.fallbackHint = nil
        }
    }
}

// MARK: - Studio switching

extension PlaybackSession {
    /// Switches playback to the given studio. If we already resolved its
    /// streams (instant case), just selects the matching MediaSource; otherwise
    /// asks the registered adapter to resolve that one studio on demand and
    /// appends the new streams to `availableSources` before selecting.
    func selectStudioAndLoad(studioId: Int) async {
        // Already resolved → instant switch.
        if let match = StreamSelector.pickSource(
            in: availableSources,
            forStudioId: studioId,
            qualityHint: selectedSource?.qualityLabel
        ) {
            preferredTranslationId = studioId
            select(source: match, autoLoadPlayerItem: false)
            engine.load(url: match.streamURL, autoPlay: true)
            NetworkLogStore.shared.logUIEvent(
                "watch_studio_switch_instant studio_id=\(studioId) quality=\(match.qualityLabel)"
            )
            return
        }
        guard let studio = availableStudios.first(where: { $0.studioId == studioId }) else {
            NetworkLogStore.shared.logUIEvent(
                "watch_studio_switch_skip studio_id=\(studioId) reason=not_in_catalog"
            )
            return
        }
        guard let shikimoriId = currentShikimoriId else { return }
        guard resolvingStudioId == nil else {
            NetworkLogStore.shared.logUIEvent(
                "watch_studio_switch_skip studio_id=\(studioId) reason=already_resolving"
            )
            return
        }
        resolvingStudioId = studioId
        defer { resolvingStudioId = nil }
        NetworkLogStore.shared.logUIEvent(
            "watch_studio_switch_resolve_start studio_id=\(studioId) episode=\(currentEpisode)"
        )
        let request = SourceResolutionRequest(
            shikimoriId: shikimoriId,
            episode: currentEpisode,
            preferredTranslationId: studioId
        )
        do {
            let streams = try await sourceRegistry.resolveStudio(
                provider: studio.provider,
                request: request,
                studioId: studioId
            )
            let title = selectedSource?.title ?? ""
            let appended: [MediaSource] = streams.map { stream in
                MediaSource(
                    provider: studio.provider,
                    streamURL: stream.url,
                    qualityLabel: stream.qualityLabel,
                    studioLabel: stream.studioLabel,
                    studioId: stream.studioId,
                    openingRangeSeconds: stream.openingRangeSeconds,
                    endingRangeSeconds: stream.endingRangeSeconds,
                    episode: currentEpisode,
                    title: title
                )
            }
            // Skip duplicates by streamURL — repeated picks of the same studio
            // (e.g. the user toggling back and forth) should not bloat the list.
            for source in appended where !availableSources.contains(where: { $0.streamURL == source.streamURL }) {
                availableSources.append(source)
            }
            guard let match = StreamSelector.pickSource(
                in: availableSources,
                forStudioId: studioId,
                qualityHint: selectedSource?.qualityLabel
            ) else {
                NetworkLogStore.shared.logAppError(
                    "watch_studio_switch_resolve_no_match studio_id=\(studioId)"
                )
                lastError = .noStreamFound
                return
            }
            preferredTranslationId = studioId
            select(source: match, autoLoadPlayerItem: false)
            engine.load(url: match.streamURL, autoPlay: true)
            NetworkLogStore.shared.logUIEvent(
                "watch_studio_switch_resolve_ok studio_id=\(studioId) streams=\(appended.count)"
            )
        } catch {
            diagnostics.log("studio switch failed studio_id=\(studioId) err=\(error.localizedDescription)")
            NetworkLogStore.shared.logAppError(
                "watch_studio_switch_resolve_fail studio_id=\(studioId) err=\(error.localizedDescription)"
            )
            if let playerError = error as? PlayerError {
                lastError = playerError
            } else {
                lastError = .streamBuildFailed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Prefetch (N+1)

extension PlaybackSession {
    /// Forwards the engine tick into PrefetchCoordinator with all the context
    /// it needs. Once the current episode is watched past the trigger ratio,
    /// the coordinator kicks off a background resolve of N+1.
    func maybeTriggerPrefetch() {
        prefetchCoordinator.evaluateTick(
            currentShikimoriId: currentShikimoriId,
            currentEpisode: currentEpisode,
            position: engine.currentTime,
            duration: engine.duration,
            availableEpisodes: availableEpisodes,
            title: selectedSource?.title ?? "",
            preferredTranslationId: preferredTranslationId
        )
    }

    /// Direct entry point used by tests / explicit callers — bypasses the
    /// trigger heuristic and asks the coordinator to resolve an episode now.
    func prefetchEpisode(_ episode: Int) async {
        guard let shikimoriId = currentShikimoriId else { return }
        await prefetchCoordinator.prefetchEpisode(
            episode,
            shikimoriId: shikimoriId,
            title: selectedSource?.title ?? "",
            preferredTranslationId: preferredTranslationId
        )
    }
}

// MARK: - Auto skip (opening / ending)

extension PlaybackSession {
    /// Reset the per-episode auto-skip "already fired" flags. Called whenever
    /// the episode or selected source changes so a re-entry into a range can
    /// trigger again on the new context.
    func resetAutoSkipFlags() {
        firedAutoSkips.removeAll()
    }

    /// Periodic-tick handler that fires from the same `engine.$currentTime`
    /// publisher used by prefetch. When the user has enabled the toggle in
    /// Settings, jumps to the end of the active opening / ending range exactly
    /// once per episode per kind. Manual rewinds back into an already-skipped
    /// range will NOT re-fire (see `firedAutoSkips`).
    func maybeAutoSkipSection() {
        guard autoSkipEnabled else { return }
        // AVPlayer reports `currentTime` in 0.25s increments; the seek itself
        // can land a few hundred ms before `upperBound`. Without a guard the
        // tick that fires immediately after the seek would re-evaluate the
        // same range and try to trigger again.
        let now = engine.currentTime
        guard now.isFinite, now >= 0 else { return }
        let duration = engine.duration
        guard duration > 0 else { return }
        let episode = currentEpisode
        // Opening first — both ranges should never overlap in practice but if
        // they do, opening wins (matches the manual-skip button precedence).
        if let opening = currentOpeningRangeSeconds,
           shouldAutoSkip(range: opening, current: now, kind: .opening, episode: episode) {
            performAutoSkip(toUpperBoundOf: opening, kind: .opening, episode: episode)
            return
        }
        if let ending = currentEndingRangeSeconds,
           shouldAutoSkip(range: ending, current: now, kind: .ending, episode: episode) {
            performAutoSkip(toUpperBoundOf: ending, kind: .ending, episode: episode)
        }
    }

    private func shouldAutoSkip(
        range: ClosedRange<Double>,
        current: Double,
        kind: PlayerSegmentKind,
        episode: Int
    ) -> Bool {
        let key = AutoSkipKey(episode: episode, kind: kind)
        if firedAutoSkips.contains(key) { return false }
        // Tolerance window: AVPlayer seek lands a few frames short of the
        // requested target. Without the 0.5s buffer, the tick right after the
        // seek would re-enter the range and the guard above would catch it on
        // the second tick — but skipping that wasted iteration keeps the log
        // clean and avoids flicker.
        guard current >= range.lowerBound, current <= max(range.upperBound - 0.5, range.lowerBound) else {
            return false
        }
        return true
    }

    private func performAutoSkip(
        toUpperBoundOf range: ClosedRange<Double>,
        kind: PlayerSegmentKind,
        episode: Int
    ) {
        let target = min(range.upperBound, max(engine.duration - 1, 0))
        firedAutoSkips.insert(AutoSkipKey(episode: episode, kind: kind))
        engine.seek(seconds: target)
        NetworkLogStore.shared.logUIEvent(
            "watch_auto_skip kind=\(kind.rawValue) episode=\(episode)"
            + " from=\(Int(engine.currentTime)) to=\(Int(target))"
        )
    }
}
