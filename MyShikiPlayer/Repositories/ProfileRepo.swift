//
//  ProfileRepo.swift
//  MyShikiPlayer
//
//  Profile cache: profile + favorites by userId. TTL 10 minutes — stats
//  shift after each userRate change, so there is no point in caching
//  aggressively.
//
//  Favourites are stored as `[AnimeListItem]` — exactly the shape the
//  catalog uses. The pipeline is also the same: REST `/api/animes?ids=…`
//  with `censored=false` (favourites are an explicit user choice, no
//  filtering) followed by `PosterEnricher.enriched(...)` for any
//  `missing_*` items. Cards render through the same `CatalogPoster` and
//  fall back to the same striped placeholder.
//

import Foundation

@MainActor
final class ProfileRepo {
    static let shared = ProfileRepo()

    // Bumped from `profile.json` to discard snapshots saved by older
    // versions whose favourites were the lighter UserFavouriteAnime shape.
    private static let diskFilename = "profile-v2.json"

    private init() {
        let loaded = DiskBackup.load(into: cache, filename: Self.diskFilename)
        if loaded > 0 {
            NetworkLogStore.shared.logUIEvent("profile_repo_disk_loaded users=\(loaded)")
        }
        // Best-effort cleanup of the previous-format dump.
        DiskBackup.remove(filename: "profile.json")
        subscribeToCacheEvents()
    }

    struct Snapshot: Equatable, Codable {
        let profile: UserProfile
        let favourites: [AnimeListItem]
    }

    private let cache = TTLCache<Int, Snapshot>(ttl: 10 * 60)
    private var pending: [Int: Task<Snapshot, Error>] = [:]

    func cachedSnapshot(userId: Int, allowStale: Bool = false) -> Snapshot? {
        allowStale ? cache.getStale(userId) : cache.get(userId)
    }

    func snapshot(
        configuration: ShikimoriConfiguration,
        userId: Int,
        forceRefresh: Bool = false
    ) async throws -> Snapshot {
        if !forceRefresh, let cached = cache.get(userId) {
            NetworkLogStore.shared.logUIEvent("profile_repo_hit id=\(userId)")
            return cached
        }
        if let existing = pending[userId] { return try await existing.value }

        let task = Task<Snapshot, Error> { [weak self] in
            defer { self?.pending.removeValue(forKey: userId) }
            let rest = ShikimoriRESTClient(configuration: configuration)
            async let profile = rest.userProfile(id: userId)
            async let favourites = rest.userFavourites(id: userId)
            let rawFavs = (try? await favourites)?.animes ?? []
            let favs = await Self.loadFavouriteListItems(
                rest: rest,
                configuration: configuration,
                rawFavs: rawFavs
            )
            let snap = try Snapshot(
                profile: await profile,
                favourites: favs
            )
            self?.cache.set(snap, for: userId)
            if let strongSelf = self {
                DiskBackup.save(cache: strongSelf.cache, filename: Self.diskFilename)
            }
            NetworkLogStore.shared.logUIEvent(
                "profile_repo_loaded id=\(userId) fav=\(snap.favourites.count)"
            )
            return snap
        }
        pending[userId] = task
        return try await task.value
    }

    func invalidate(userId: Int) {
        cache.invalidate(userId)
        pending[userId]?.cancel()
        pending.removeValue(forKey: userId)
        DiskBackup.save(cache: cache, filename: Self.diskFilename)
    }

    func invalidateAll() {
        cache.invalidateAll()
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        DiskBackup.remove(filename: Self.diskFilename)
    }

    // MARK: - Favourites loader

    /// Re-fetches favourites as `AnimeListItem`s through the same pipeline
    /// the catalog uses: REST `/api/animes?ids=…&censored=false` for the
    /// fields, then `PosterEnricher.enriched(...)` for any `missing_*`
    /// posters. Order matches the original favourites list.
    private static func loadFavouriteListItems(
        rest: ShikimoriRESTClient,
        configuration: ShikimoriConfiguration,
        rawFavs: [UserFavouriteAnime]
    ) async -> [AnimeListItem] {
        guard !rawFavs.isEmpty else { return [] }
        let orderedIds = rawFavs.map(\.id)

        let batchSize = 50
        var fetchedById: [Int: AnimeListItem] = [:]
        let chunks = stride(from: 0, to: orderedIds.count, by: batchSize).map { offset -> [Int] in
            Array(orderedIds[offset..<min(offset + batchSize, orderedIds.count)])
        }
        for chunk in chunks {
            var query = AnimeListQuery()
            query.ids = chunk.map(String.init).joined(separator: ",")
            query.limit = chunk.count
            // Favourites are an explicit user choice — disable the default
            // adult-rating filter so nothing gets dropped.
            query.censored = false
            do {
                let items = try await rest.animes(query: query)
                for item in items {
                    fetchedById[item.id] = item
                }
            } catch {
                NetworkLogStore.shared.logAppError(
                    "profile_repo_favs_fetch_failed ids=\(chunk.count) err=\(error.localizedDescription)"
                )
            }
        }

        // Preserve favourites order; drop anything REST didn't return (rare —
        // happens for deleted titles).
        let inOrder = orderedIds.compactMap { fetchedById[$0] }
        // Same poster enrichment path the catalog uses.
        return await PosterEnricher.shared.enriched(configuration: configuration, items: inOrder)
    }

    // MARK: - Event subscriptions (Iter 4)

    private func subscribeToCacheEvents() {
        // user-rate stats / favorites shift — invalidate by userId.
        CacheEvents.observeAnimeMutation { [weak self] _, userId in
            self?.invalidate(userId: userId)
        }
        CacheEvents.observeClearAll { [weak self] in
            self?.invalidateAll()
        }
    }
}
