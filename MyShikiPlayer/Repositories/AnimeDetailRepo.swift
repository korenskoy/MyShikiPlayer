//
//  AnimeDetailRepo.swift
//  MyShikiPlayer
//
//  Bundles detail + stats + Kodik catalog + screenshots + videos + related
//  into a single Snapshot, cached for 30 minutes per id.
//  - Request deduplication: three screens asking for the same id share one HTTP.
//  - Manual invalidation on mutations (like / status / episode watched).
//

import Foundation

/// Abstraction over the per-anime snapshot store. Lets `AnimeDetailsViewModel`
/// be tested without touching the live singleton, network, or disk cache.
@MainActor
protocol AnimeDetailsRepository: AnyObject {
    func cachedSnapshot(id: Int, allowStale: Bool) -> AnimeDetailRepo.Snapshot?
    func snapshot(
        id: Int,
        configuration: ShikimoriConfiguration,
        kodikClient: KodikClient,
        forceRefresh: Bool
    ) async throws -> AnimeDetailRepo.Snapshot
}

@MainActor
final class AnimeDetailRepo: AnimeDetailsRepository {
    static let shared = AnimeDetailRepo()

    private let session: URLSession
    private let diskFilename: String
    /// Instances other than `shared` are short-lived (tests), so the
    /// cache-event subscriptions have to go away with them.
    private let cacheObservers = CacheObserverBag()

    /// `session` and `diskFilename` are injectable so a test can drive the repo
    /// through a stubbed `URLProtocol` and its own throwaway backup file.
    /// Production keeps using `shared`.
    init(session: URLSession = .shared, diskFilename: String = "anime-detail.json") {
        self.session = session
        self.diskFilename = diskFilename
        let loaded = DiskBackup.load(into: cache, filename: diskFilename)
        if loaded > 0 {
            NetworkLogStore.shared.logUIEvent("anime_detail_repo_disk_loaded count=\(loaded)")
        }
        subscribeToCacheEvents()
    }

    struct Snapshot: Codable {
        let detail: AnimeDetail
        let stats: GraphQLAnimeStatsEntry?
        let kodikCatalog: [KodikCatalogEntry]
        let screenshots: [AnimeScreenshotREST]
        let videos: [AnimeVideoREST]
        let related: [AnimeListItem]
        /// Other titles from the same Shikimori franchise, ordered by aired_on.
        /// Distinct from `related` (which mixes genre + franchise) and rendered
        /// as its own section in the details view.
        let franchiseItems: [AnimeListItem]

        init(
            detail: AnimeDetail,
            stats: GraphQLAnimeStatsEntry?,
            kodikCatalog: [KodikCatalogEntry],
            screenshots: [AnimeScreenshotREST],
            videos: [AnimeVideoREST],
            related: [AnimeListItem],
            franchiseItems: [AnimeListItem]
        ) {
            self.detail = detail
            self.stats = stats
            self.kodikCatalog = kodikCatalog
            self.screenshots = screenshots
            self.videos = videos
            self.related = related
            self.franchiseItems = franchiseItems
        }

        // Older on-disk snapshots predate `franchiseItems` — decode it as empty
        // when missing instead of failing the whole snapshot.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            detail = try c.decode(AnimeDetail.self, forKey: .detail)
            stats = try c.decodeIfPresent(GraphQLAnimeStatsEntry.self, forKey: .stats)
            kodikCatalog = try c.decode([KodikCatalogEntry].self, forKey: .kodikCatalog)
            screenshots = try c.decode([AnimeScreenshotREST].self, forKey: .screenshots)
            videos = try c.decode([AnimeVideoREST].self, forKey: .videos)
            related = try c.decode([AnimeListItem].self, forKey: .related)
            franchiseItems = try c.decodeIfPresent([AnimeListItem].self, forKey: .franchiseItems) ?? []
        }
    }

    // A snapshot bundles detail + screenshots + videos + related + up to 100
    // franchise items, so it is by far the heaviest thing we persist — hence
    // a tighter bound than the TTLCache default.
    private let cache = TTLCache<Int, Snapshot>(ttl: 30 * 60, maxEntries: 80)
    private var pending: [Int: Task<Snapshot, Error>] = [:]

    /// Instant synchronous access to the cache — no network.
    /// `allowStale: true` also returns expired values (for SWR rendering of
    /// "what we had" while a fresh fetch is in flight in the background).
    /// Mirrors the kodikCatalog SWR done by `snapshot(...)` so the first
    /// fast-path render of detail screen never shows an empty dub picker
    /// when KodikCatalogRepo already has data.
    func cachedSnapshot(id: Int, allowStale: Bool = false) -> Snapshot? {
        let raw = allowStale ? cache.getStale(id) : cache.get(id)
        guard let cached = raw else { return nil }
        guard cached.kodikCatalog.isEmpty,
              let fresh = KodikCatalogRepo.shared.cachedCatalog(shikimoriId: id, allowStale: true),
              !fresh.isEmpty
        else {
            return cached
        }
        let merged = Snapshot(
            detail: cached.detail,
            stats: cached.stats,
            kodikCatalog: fresh,
            screenshots: cached.screenshots,
            videos: cached.videos,
            related: cached.related,
            franchiseItems: cached.franchiseItems
        )
        cache.set(merged, for: id)
        return merged
    }

    /// Main entry point: returns cached value (if TTL is valid) or makes a
    /// fresh request. All concurrent calls with the same id are coalesced.
    func snapshot(
        id: Int,
        configuration: ShikimoriConfiguration,
        kodikClient: KodikClient = KodikClient(),
        forceRefresh: Bool = false
    ) async throws -> Snapshot {
        if !forceRefresh, let cached = cache.get(id) {
            // SWR for kodikCatalog: AnimeDetailRepo and KodikCatalogRepo cache
            // independently. If our snapshot was first stored when the Kodik
            // call returned empty (transient ban / token glitch / network),
            // we would otherwise serve a stale-empty catalog for 30 minutes
            // while KodikCatalogRepo already has fresh data populated by
            // another flow (e.g. KodikAdapter on "Watch episode"). Adopt that
            // data on hit so the user sees dub options instead of an empty
            // list.
            if cached.kodikCatalog.isEmpty,
               let fresh = KodikCatalogRepo.shared.cachedCatalog(shikimoriId: id, allowStale: true),
               !fresh.isEmpty {
                let updated = Snapshot(
                    detail: cached.detail,
                    stats: cached.stats,
                    kodikCatalog: fresh,
                    screenshots: cached.screenshots,
                    videos: cached.videos,
                    related: cached.related,
                    franchiseItems: cached.franchiseItems
                )
                cache.set(updated, for: id)
                DiskBackup.save(cache: cache, filename: diskFilename)
                NetworkLogStore.shared.logUIEvent(
                    "anime_detail_repo_kodik_resync id=\(id) entries=\(fresh.count)"
                )
                return updated
            }
            NetworkLogStore.shared.logUIEvent(
                "anime_detail_repo_hit id=\(id) kodik_count=\(cached.kodikCatalog.count)"
            )
            return cached
        }
        if let existing = pending[id] {
            NetworkLogStore.shared.logUIEvent("anime_detail_repo_join_pending id=\(id)")
            return try await existing.value
        }
        NetworkLogStore.shared.logUIEvent(
            "anime_detail_repo_fetch_start id=\(id) force_refresh=\(forceRefresh)"
        )

        let session = self.session
        let task = Task<Snapshot, Error> { [weak self] in
            defer { self?.pending.removeValue(forKey: id) }

            let rest = ShikimoriRESTClient(configuration: configuration, session: session)
            let gql = ShikimoriGraphQLClient(configuration: configuration, session: session)

            async let detailAsync: AnimeDetail = rest.anime(id: id)
            async let statsAsync: GraphQLAnimeStatsEntry? = try? await gql.animeStats(id: id)
            async let kodikAsync: [KodikCatalogEntry] = Self.loadKodikCatalog(
                id: id,
                client: kodikClient
            )
            async let screenshotsAsync: [AnimeScreenshotREST] = (
                try? await rest.animeScreenshots(id: id)
            ) ?? []
            async let videosAsync: [AnimeVideoREST] = (
                try? await rest.animeVideos(id: id)
            ) ?? []

            let detail = try await detailAsync
            let stats = await statsAsync
            let kodik = await kodikAsync
            let shots = await screenshotsAsync
            let videos = await videosAsync

            let statsLabel = stats == nil ? "nil" : "ok"
            NetworkLogStore.shared.logUIEvent(
                "anime_detail_repo_fetch_pieces id=\(id)"
                + " kodik=\(kodik.count) shots=\(shots.count)"
                + " videos=\(videos.count) stats=\(statsLabel)"
            )

            let relatedRaw = await Self.loadRelated(detail: detail, rest: rest)
            let related = await PosterEnricher.shared.enriched(
                configuration: configuration,
                items: relatedRaw
            )

            let franchiseRaw = await Self.loadFranchise(detail: detail, rest: rest)
            let franchiseItems = await PosterEnricher.shared.enriched(
                configuration: configuration,
                items: franchiseRaw
            )

            let snapshot = Snapshot(
                detail: detail,
                stats: stats,
                kodikCatalog: kodik,
                screenshots: shots,
                videos: videos,
                related: related,
                franchiseItems: franchiseItems
            )
            self?.cache.set(snapshot, for: id)
            if let strongSelf = self {
                DiskBackup.save(cache: strongSelf.cache, filename: strongSelf.diskFilename)
            }
            NetworkLogStore.shared.logUIEvent(
                "anime_detail_repo_cached id=\(id) shots=\(shots.count) videos=\(videos.count)"
            )
            return snapshot
        }
        pending[id] = task
        return try await task.value
    }

    /// Drop the cache for a specific title. Call after user-rate / favorite
    /// mutations / after the player closes (so the next load returns a fresh
    /// userRate.episodes).
    func invalidate(id: Int) {
        cache.invalidate(id)
        if let task = pending[id] {
            task.cancel()
            pending.removeValue(forKey: id)
        }
        DiskBackup.save(cache: cache, filename: diskFilename)
    }

    func invalidateAll() {
        cache.invalidateAll()
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        DiskBackup.remove(filename: diskFilename)
    }

    // MARK: - Event subscriptions (Iter 4)

    private func subscribeToCacheEvents() {
        // user-rate / favorite — partial invalidate by animeId.
        cacheObservers.add(CacheEvents.observeAnimeMutation { [weak self] animeId, _ in
            self?.invalidate(id: animeId)
        })
        cacheObservers.add(CacheEvents.observeClearAll { [weak self] in
            self?.invalidateAll()
        })
    }

    // MARK: - Loaders (same ones that used to live in AnimeDetailsViewModel)

    private static func loadKodikCatalog(
        id: Int,
        client: KodikClient
    ) async -> [KodikCatalogEntry] {
        NetworkLogStore.shared.logUIEvent("anime_detail_repo_kodik_load_start id=\(id)")

        guard let token = KodikTokenManager.resolveToken() else {
            NetworkLogStore.shared.logUIEvent("anime_detail_repo_kodik_skip id=\(id) reason=no_token")
            return await staleKodikFallback(id: id, reason: "no_token") ?? []
        }

        do {
            let result = try await KodikCatalogRepo.shared.catalog(
                shikimoriId: id,
                token: token,
                client: client
            )
            // Per `feedback_player_resilience.md`: never drop a previously
            // valid catalog because of a transient empty/banned response.
            // If the network call returned 0 entries but a stale catalog
            // exists in KodikCatalogRepo, prefer the stale one over `[]`.
            if result.isEmpty {
                if let stale = await staleKodikFallback(id: id, reason: "empty_response"),
                   !stale.isEmpty {
                    return stale
                }
                NetworkLogStore.shared.logUIEvent(
                    "anime_detail_repo_kodik_load_ok id=\(id) entries=0"
                )
                return []
            }
            NetworkLogStore.shared.logUIEvent(
                "anime_detail_repo_kodik_load_ok id=\(id) entries=\(result.count)"
            )
            return result
        } catch {
            NetworkLogStore.shared.logAppError(
                "anime_detail_repo_kodik_failed id=\(id) \(error.localizedDescription)"
            )
            return await staleKodikFallback(id: id, reason: "load_error") ?? []
        }
    }

    /// Returns the stale Kodik catalog if KodikCatalogRepo still has data for
    /// the given id, otherwise nil. Used as a last-resort fallback so a
    /// transient empty/banned response does not wipe the dub picker.
    private static func staleKodikFallback(
        id: Int,
        reason: String
    ) async -> [KodikCatalogEntry]? {
        let stale = await KodikCatalogRepo.shared.cachedCatalog(shikimoriId: id, allowStale: true)
        guard let stale, !stale.isEmpty else { return nil }
        NetworkLogStore.shared.logUIEvent(
            "anime_detail_repo_kodik_fallback_stale id=\(id) entries=\(stale.count) reason=\(reason)"
        )
        return stale
    }

    private static func loadRelated(
        detail: AnimeDetail,
        rest: ShikimoriRESTClient
    ) async -> [AnimeListItem] {
        var collected: [AnimeListItem] = []
        var seen = Set<Int>([detail.id])
        func append(_ items: [AnimeListItem]) {
            for item in items where !seen.contains(item.id) && collected.count < 12 {
                seen.insert(item.id)
                collected.append(item)
            }
        }

        if let firstGenre = detail.genres?.compactMap(\.id).first {
            var q = AnimeListQuery()
            q.limit = 12
            q.genre = String(firstGenre)
            q.kind = detail.kind
            q.excludeIds = String(detail.id)
            if let items = try? await rest.animes(query: q) { append(items) }
        }
        if collected.count < 12, let franchise = detail.franchise, !franchise.isEmpty {
            var q = AnimeListQuery()
            q.limit = 12
            q.franchise = franchise
            q.excludeIds = String(detail.id)
            if let items = try? await rest.animes(query: q) { append(items) }
        }
        return collected
    }

    /// Other titles from the same franchise, ordered by air date. Distinct
    /// from `loadRelated` (genre + franchise mix) — this powers the dedicated
    /// "Другие части" section. Returns empty if the title has no franchise id.
    /// Shikimori caps `/api/animes` at 50 items per page, so we paginate up
    /// to `desiredTotal` items.
    private static func loadFranchise(
        detail: AnimeDetail,
        rest: ShikimoriRESTClient,
        desiredTotal: Int = 100,
        pageSize: Int = 50
    ) async -> [AnimeListItem] {
        guard let franchise = detail.franchise, !franchise.isEmpty else { return [] }
        var collected: [AnimeListItem] = []
        var seen = Set<Int>([detail.id])
        var page = 1
        let maxPages = max(1, (desiredTotal + pageSize - 1) / pageSize)

        while collected.count < desiredTotal && page <= maxPages {
            var q = AnimeListQuery()
            q.limit = pageSize
            q.page = page
            q.franchise = franchise
            q.order = AnimeOrder.airedOn.rawValue
            q.excludeIds = String(detail.id)
            guard let batch = try? await rest.animes(query: q), !batch.isEmpty else { break }
            for item in batch where !seen.contains(item.id) {
                seen.insert(item.id)
                collected.append(item)
                if collected.count >= desiredTotal { break }
            }
            // Shikimori sometimes echoes the same page when there's no next —
            // stop early if the batch was short.
            if batch.count < pageSize { break }
            page += 1
        }
        // Strict chronological ascending order — Shikimori's `aired_on=desc`
        // sometimes interleaves specials and movies out of date order, so we
        // resort client-side. ISO date strings compare correctly. Items with
        // no date at all go to the end.
        return collected.sorted { lhs, rhs in
            let l = airedOnKey(lhs)
            let r = airedOnKey(rhs)
            switch (l, r) {
            case let (l?, r?):     return l < r
            case (.some, .none):   return true
            case (.none, .some):   return false
            case (.none, .none):   return false
            }
        }
    }

    /// Best-effort date key for franchise ordering: prefer `airedOn`, fall
    /// back to `releasedOn`. Empty strings count as missing.
    private static func airedOnKey(_ item: AnimeListItem) -> String? {
        if let s = item.airedOn, !s.isEmpty { return s }
        if let s = item.releasedOn, !s.isEmpty { return s }
        return nil
    }
}
