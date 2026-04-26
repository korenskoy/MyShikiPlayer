//
//  AnimeDetailsViewModel.swift
//  MyShikiPlayer
//
//  Loads and mutates data for the new anime detail screen:
//  - AnimeDetail from Shikimori REST,
//  - scoresStats + statusesStats from Shikimori GraphQL (for the community block),
//  - Kodik catalog (for episode list and studio count),
//  - related (through REST by genre + franchise).
//
//  The playback layer (PlaybackSession) is driven externally — the VM only
//  calls prepare/select/load and exposes session to the caller for opening
//  the window.
//

import Foundation
import Combine

@MainActor
final class AnimeDetailsViewModel: ObservableObject {
    @Published private(set) var state: AnimeDetailsLoadState = .idle
    @Published private(set) var detail: AnimeDetail?
    @Published private(set) var stats: GraphQLAnimeStatsEntry?
    @Published private(set) var catalogEntries: [KodikCatalogEntry] = []
    @Published private(set) var related: [AnimeListItem] = []
    @Published private(set) var allScreenshots: [AnimeScreenshotREST] = []
    @Published private(set) var allVideos: [AnimeVideoREST] = []
    @Published private(set) var selectedTranslationId: Int?
    @Published private(set) var userStatus: String?
    @Published private(set) var userScore: Int?
    @Published private(set) var userRateId: Int?
    @Published private(set) var userEpisodesWatched: Int = 0
    @Published private(set) var isFavorite: Bool = false
    @Published private(set) var isUpdatingList: Bool = false
    @Published private(set) var isUpdatingFavorite: Bool = false
    @Published private(set) var isPreparingPlayback: Bool = false

    let shikimoriId: Int
    let session: PlaybackSession
    private let configuration: ShikimoriConfiguration
    private let currentUserId: Int?
    private let restClient: ShikimoriRESTClient
    private let graphqlClient: ShikimoriGraphQLClient
    private let kodikClient: KodikClient
    private let repository: AnimeDetailsRepository

    /// Cross-title "remember last studio" memory + preferred-translation
    /// resolver lives here (Phase 4 split — keeps the picker rule in one place).
    private let studioPicker = StudioPickerVM()

    init(
        shikimoriId: Int,
        configuration: ShikimoriConfiguration,
        currentUserId: Int?,
        session: PlaybackSession? = nil,
        kodikClient: KodikClient = .init(),
        repository: AnimeDetailsRepository = AnimeDetailRepo.shared,
        urlSession: URLSession = .shared
    ) {
        self.shikimoriId = shikimoriId
        self.configuration = configuration
        self.currentUserId = currentUserId
        self.session = session ?? PlaybackSession()
        self.restClient = ShikimoriRESTClient(configuration: configuration, session: urlSession)
        self.graphqlClient = ShikimoriGraphQLClient(configuration: configuration, session: urlSession)
        self.kodikClient = kodikClient
        self.repository = repository
    }

    // MARK: - Derived

    var title: String {
        detail?.russian.flatMap { $0.isEmpty ? nil : $0 } ?? detail?.name ?? "—"
    }

    var romajiTitle: String { detail?.name ?? "" }

    /// Title is in the "Announcement" status — no episodes; player/score/episodes UI is hidden.
    var isAnons: Bool {
        detail?.blocksPlaybackBecauseAnon ?? false
    }

    /// Max episodes for the grid. Taken from Kodik catalog if available, otherwise fallback.
    var episodeCount: Int {
        EpisodesLoader.episodeCount(
            catalogEntries: catalogEntries,
            selectedTranslationId: selectedTranslationId,
            detail: detail,
            userEpisodesWatched: userEpisodesWatched
        )
    }

    /// Episodes confirmed available in Kodik (for the "has/missing" grid markup).
    var episodesWithSources: Set<Int> {
        EpisodesLoader.episodesWithSources(
            catalogEntries: catalogEntries,
            selectedTranslationId: selectedTranslationId
        )
    }

    var uniqueStudiosCount: Int {
        EpisodesLoader.uniqueStudiosCount(catalogEntries: catalogEntries)
    }

    /// Episode previews from `/api/animes/{id}/videos`, filtered by
    /// `kind == "episode_preview"`. Key is episode number (from `name`,
    /// usually a zero-padded string like "07").
    var episodePreviews: [Int: URL] {
        EpisodesLoader.episodePreviews(from: allVideos)
    }

    /// Only "real" trailers/clips — without per-episode previews (those live
    /// in EpisodeGrid, not TrailersSection).
    var trailerVideos: [AnimeVideoREST] {
        EpisodesLoader.trailerVideos(from: allVideos)
    }

    /// Best poster URL: prefer GraphQL (its `mainUrl`/`originalUrl` are the
    /// canonical links), fall back to the REST image, skipping every
    /// `/assets/globals/missing_*.jpg` placeholder Shikimori serves for titles
    /// without artwork. Aligns with `PosterEnricher`, `HomeSectionsRepo`,
    /// `CatalogPoster`, `ProfileRepo`, and `TopicDetailView`.
    var posterURL: URL? {
        if let raw = stats?.poster?.originalUrl ?? stats?.poster?.mainUrl,
           !raw.isEmpty, !raw.contains("missing_") {
            return raw.shikimoriResolvedURL
        }
        let raw = nonMissing(detail?.image?.original)
            ?? nonMissing(detail?.image?.preview)
            ?? nonMissing(detail?.image?.x96)
            ?? nonMissing(detail?.image?.x48)
        return raw?.shikimoriResolvedURL
    }

    private func nonMissing(_ s: String?) -> String? {
        guard let s, !s.isEmpty, !s.contains("missing_") else { return nil }
        return s
    }

    /// Next episode for the "Watch" button (userEpisodesWatched + 1, clamped).
    var nextEpisodeToWatch: Int {
        let next = userEpisodesWatched + 1
        return max(1, min(next, episodeCount))
    }

    // MARK: - Load

    func load(forceRefresh: Bool = false) async {
        state = .loading
        do {
            // SWR: render any saved snapshot (even stale) immediately, then
            // refresh in the background through `snapshot()` and replace the UI.
            if !forceRefresh, let cached = repository.cachedSnapshot(id: shikimoriId, allowStale: true) {
                apply(snapshot: cached)
                state = .content
            }

            let snapshot = try await repository.snapshot(
                id: shikimoriId,
                configuration: configuration,
                kodikClient: kodikClient,
                forceRefresh: forceRefresh
            )
            apply(snapshot: snapshot)
            state = .content
        } catch {
            // If we already rendered a cached snapshot, keep it on screen
            // instead of flipping into error — we only surface an error when
            // there is nothing to show.
            if detail == nil {
                state = .error(error.localizedDescription)
            }
        }
    }

    private func apply(snapshot: AnimeDetailRepo.Snapshot) {
        let prevCount = catalogEntries.count
        let nextCount = snapshot.kodikCatalog.count
        let overwriteEmpty = prevCount > 0 && nextCount == 0
        NetworkLogStore.shared.logUIEvent(
            "details_vm_apply_snapshot id=\(shikimoriId)"
            + " prev_kodik=\(prevCount) next_kodik=\(nextCount)"
            + " overwrite_with_empty=\(overwriteEmpty)"
        )

        detail = snapshot.detail
        stats = snapshot.stats
        catalogEntries = snapshot.kodikCatalog
        allScreenshots = snapshot.screenshots
        allVideos = snapshot.videos
        related = snapshot.related

        if let rate = snapshot.detail.userRate {
            userRateId = rate.id
            userStatus = rate.status
            userScore = rate.score
            userEpisodesWatched = rate.episodes ?? 0
        } else {
            userRateId = nil
            userStatus = nil
            userScore = nil
            userEpisodesWatched = 0
        }

        isFavorite = snapshot.detail.favoured ?? false

        selectedTranslationId = resolvePreferredTranslationId()
        persistStudioName(forTranslationId: selectedTranslationId)
    }

    // MARK: - User rate mutations

    func setStatus(_ status: String?) async {
        isUpdatingList = true
        defer { isUpdatingList = false }
        await applyUserRateMutation(status: status, score: userScore)
    }

    func setScore(_ score: Int?) async {
        isUpdatingList = true
        defer { isUpdatingList = false }
        await applyUserRateMutation(status: userStatus ?? "planned", score: score)
    }

    private func applyUserRateMutation(status: String?, score: Int?) async {
        guard let userId = currentUserId else { return }
        do {
            if let rateId = userRateId {
                // Update
                let body = UserRateV2UpdateBody(userRate: .init(
                    chapters: nil, episodes: nil, volumes: nil, rewatches: nil,
                    score: score.map(String.init), status: status, text: nil
                ))
                let updated = try await restClient.updateUserRate(id: rateId, body: body)
                userStatus = updated.status
                userScore = updated.score
                userEpisodesWatched = updated.episodes
            } else {
                // Create
                guard let status else { return }
                let body = UserRateV2CreateBody(userRate: .init(
                    userId: String(userId),
                    targetId: String(shikimoriId),
                    targetType: "Anime",
                    status: status,
                    score: score.map(String.init),
                    chapters: nil, episodes: nil, volumes: nil, rewatches: nil, text: nil
                ))
                let created = try await restClient.createUserRate(body)
                userRateId = created.id
                userStatus = created.status
                userScore = created.score
                userEpisodesWatched = created.episodes
            }
            // The title data now contains the updated userRate — post the event;
            // subscribed repos (AnimeDetail / Home / Profile) will clear their caches.
            CacheEvents.postUserRateChanged(animeId: shikimoriId, userId: userId)
        } catch {
            NetworkLogStore.shared.logAppError("details_user_rate_mutation_failed \(error.localizedDescription)")
        }
    }

    /// Marks an episode as watched in user_rate. Never decreases the counter
    /// (rewatches do not roll back progress), idempotent (if already marked —
    /// no network call). If user_rate does not exist yet — creates one with
    /// status `watching`. Non-throwing: errors are logged, caller proceeds.
    /// When the watched episode equals the title's last episode, the status
    /// flips to `completed` in the same request — keeps the user list in sync
    /// without requiring a manual status change.
    func markEpisodeWatched(_ episode: Int) async {
        guard let userId = currentUserId else { return }
        let target = max(userEpisodesWatched, episode)
        guard target > userEpisodesWatched else { return }
        let totalEpisodes = detail?.episodeCountForPickerFallback ?? 0
        let reachesFinal = totalEpisodes > 0 && target >= totalEpisodes
        let nextStatus: String? = reachesFinal && userStatus != "completed" ? "completed" : nil
        do {
            if let rateId = userRateId {
                let body = UserRateV2UpdateBody(userRate: .init(
                    chapters: nil,
                    episodes: String(target),
                    volumes: nil,
                    rewatches: nil,
                    score: nil,
                    status: nextStatus,
                    text: nil
                ))
                let updated = try await restClient.updateUserRate(id: rateId, body: body)
                userEpisodesWatched = updated.episodes
                userStatus = updated.status
            } else {
                let body = UserRateV2CreateBody(userRate: .init(
                    userId: String(userId),
                    targetId: String(shikimoriId),
                    targetType: "Anime",
                    status: nextStatus ?? "watching",
                    score: nil,
                    chapters: nil,
                    episodes: String(target),
                    volumes: nil,
                    rewatches: nil,
                    text: nil
                ))
                let created = try await restClient.createUserRate(body)
                userRateId = created.id
                userStatus = created.status
                userEpisodesWatched = created.episodes
            }
            CacheEvents.postUserRateChanged(animeId: shikimoriId, userId: userId)
            NetworkLogStore.shared.logUIEvent(
                "details_episode_synced shikimori_id=\(shikimoriId) episodes=\(target) " +
                "auto_completed=\(reachesFinal && nextStatus == "completed")"
            )
        } catch {
            NetworkLogStore.shared.logAppError(
                "details_episode_sync_failed id=\(shikimoriId) ep=\(target) err=\(error.localizedDescription)"
            )
        }
    }

    // MARK: - Favorites

    func toggleFavorite() async {
        let desired = !isFavorite
        isUpdatingFavorite = true
        defer { isUpdatingFavorite = false }
        do {
            if desired {
                try await restClient.addFavorite(animeId: shikimoriId)
            } else {
                try await restClient.removeFavorite(animeId: shikimoriId)
            }
            isFavorite = desired
            // detail.favoured + Profile.favourites list changed.
            if let userId = currentUserId {
                CacheEvents.postFavoriteToggled(animeId: shikimoriId, userId: userId)
            }
        } catch {
            NetworkLogStore.shared.logAppError("details_favorite_toggle_failed \(error.localizedDescription)")
        }
    }

    // MARK: - Translations / playback

    func selectTranslation(_ id: Int?) {
        selectedTranslationId = id
        persistStudioName(forTranslationId: id)
    }

    private func resolvePreferredTranslationId() -> Int? {
        studioPicker.resolvePreferredTranslationId(
            catalogEntries: catalogEntries,
            sessionPreferred: session.preferredTranslationId,
            currentlySelected: selectedTranslationId
        )
    }

    private func persistStudioName(forTranslationId id: Int?) {
        studioPicker.persistStudioName(forTranslationId: id, in: catalogEntries)
    }

    /// Prepares PlaybackSession for the given episode. Only calls prepare +
    /// select + load source. Opening the NSWindow is done by the caller
    /// (PlayerWindowCoordinator) — AppKit is not pulled in here.
    func preparePlayback(episode: Int) async {
        guard let detail else { return }
        isPreparingPlayback = true
        defer { isPreparingPlayback = false }
        await session.prepare(
            shikimoriId: shikimoriId,
            title: detail.russian?.nilIfEmpty ?? detail.name,
            episode: episode,
            preferredTranslationId: selectedTranslationId,
            availableEpisodes: Array(1...episodeCount)
        )
        _ = session.ensureSelectedSource()
        session.loadSelectedSource(autoPlay: false)
    }
}

// MARK: - Small helper

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
