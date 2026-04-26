//
//  KodikCatalogRepo.swift
//  MyShikiPlayer
//
//  Cache for the Kodik /search catalog per shikimori_id. Single source of
//  truth for both AnimeDetailRepo (title page) and KodikAdapter (opening the
//  player) — previously every "Watch episode" tap duplicated /search even
//  though it was already in the page snapshot.
//
//  TTL 60 minutes — new episodes appear at the source once every 1-2 weeks,
//  hourly refresh is more than enough. Full invalidation comes via the
//  `cacheShouldClearAll` event (Settings → "Reset cache").
//

import Foundation

@MainActor
final class KodikCatalogRepo {
    static let shared = KodikCatalogRepo()

    private static let diskFilename = "kodik-catalog.json"
    private let cache = TTLCache<Int, [KodikCatalogEntry]>(ttl: 60 * 60)
    private var pending: [Int: Task<[KodikCatalogEntry], Error>] = [:]

    private init() {
        let loaded = DiskBackup.load(into: cache, filename: Self.diskFilename)
        if loaded > 0 {
            NetworkLogStore.shared.logUIEvent("kodik_catalog_repo_disk_loaded count=\(loaded)")
        }
        subscribeToCacheEvents()
    }

    /// Synchronous access to the cache without network. allowStale — also
    /// returns expired entries (for SWR "what we had" display while a
    /// refresh runs in the background).
    func cachedCatalog(shikimoriId: Int, allowStale: Bool = false) -> [KodikCatalogEntry]? {
        allowStale ? cache.getStale(shikimoriId) : cache.get(shikimoriId)
    }

    /// Main entry point: cached value (if TTL is valid) or a fresh request.
    /// Concurrent calls with the same shikimoriId are coalesced — one HTTP.
    func catalog(
        shikimoriId: Int,
        token: String,
        client: KodikClient = KodikClient(),
        forceRefresh: Bool = false
    ) async throws -> [KodikCatalogEntry] {
        if !forceRefresh, let cached = cache.get(shikimoriId) {
            NetworkLogStore.shared.logUIEvent(
                "kodik_catalog_repo_hit shikimori_id=\(shikimoriId) entries=\(cached.count)"
            )
            return cached
        }
        // Diagnostics: distinguish "cache empty" from "cache stale" — both
        // funnel into a network refetch but mean very different things for
        // user-visible behaviour after a player closes.
        let stale = cache.isStale(shikimoriId)
        let staleCount = cache.getStale(shikimoriId)?.count ?? -1
        NetworkLogStore.shared.logUIEvent(
            "kodik_catalog_repo_miss shikimori_id=\(shikimoriId) force=\(forceRefresh) stale=\(stale) stale_entries=\(staleCount)"
        )
        if let existing = pending[shikimoriId] {
            NetworkLogStore.shared.logUIEvent(
                "kodik_catalog_repo_join_pending shikimori_id=\(shikimoriId)"
            )
            return try await existing.value
        }

        let task = Task<[KodikCatalogEntry], Error> { [weak self] in
            defer { self?.pending.removeValue(forKey: shikimoriId) }
            do {
                let entries = try await client.loadCatalog(shikimoriId: shikimoriId, token: token)
                self?.cache.set(entries, for: shikimoriId)
                if let strongSelf = self {
                    DiskBackup.save(cache: strongSelf.cache, filename: Self.diskFilename)
                }
                NetworkLogStore.shared.logUIEvent(
                    "kodik_catalog_repo_cached shikimori_id=\(shikimoriId) entries=\(entries.count)"
                )
                return entries
            } catch {
                NetworkLogStore.shared.logAppError(
                    "kodik_catalog_repo_load_failed shikimori_id=\(shikimoriId) error=\(error.localizedDescription)"
                )
                throw error
            }
        }
        pending[shikimoriId] = task
        return try await task.value
    }

    func invalidate(shikimoriId: Int) {
        cache.invalidate(shikimoriId)
        pending[shikimoriId]?.cancel()
        pending.removeValue(forKey: shikimoriId)
        DiskBackup.save(cache: cache, filename: Self.diskFilename)
    }

    func invalidateAll() {
        cache.invalidateAll()
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        DiskBackup.remove(filename: Self.diskFilename)
    }

    private func subscribeToCacheEvents() {
        CacheEvents.observeClearAll { [weak self] in
            self?.invalidateAll()
        }
    }
}
