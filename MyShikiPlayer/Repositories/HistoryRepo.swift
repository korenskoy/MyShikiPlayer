//
//  HistoryRepo.swift
//  MyShikiPlayer
//
//  Cache for Shikimori history (`/api/users/{id}/history?target_type=Anime`).
//  The first page sits in TTLCache for 5 min (per-userId), with a disk
//  backup for cold-start. Pagination (load-more) is uncached — always fresh.
//
//  Invalidation: any user-rate / favorite mutation (your own score / status
//  change must appear in history immediately) + global wipe.
//

import Foundation

/// Abstraction over the per-user history cache.
@MainActor
protocol HistoryRepository: AnyObject {
    func cachedHistory(userId: Int, allowStale: Bool) -> [UserHistoryEntry]?
    func history(
        configuration: ShikimoriConfiguration,
        userId: Int,
        forceRefresh: Bool
    ) async throws -> [UserHistoryEntry]
    func historyPage(
        configuration: ShikimoriConfiguration,
        userId: Int,
        page: Int,
        limit: Int
    ) async throws -> [UserHistoryEntry]
}

@MainActor
final class HistoryRepo: HistoryRepository {
    static let shared = HistoryRepo()

    private static let diskFilename = "history.json"
    nonisolated static let firstPageLimit = 50

    private let cache = TTLCache<Int, [UserHistoryEntry]>(ttl: 5 * 60)
    private var pending: [Int: Task<[UserHistoryEntry], Error>] = [:]

    private init() {
        let loaded = DiskBackup.load(into: cache, filename: Self.diskFilename)
        if loaded > 0 {
            NetworkLogStore.shared.logUIEvent("history_repo_disk_loaded users=\(loaded)")
        }
        // Any user-rate/favorite mutation shifts history — invalidate at the
        // user level (the payload carries userId and the cache is keyed by it).
        CacheEvents.observeAnimeMutation { [weak self] _, userId in
            self?.invalidate(userId: userId)
        }
        CacheEvents.observeClearAll { [weak self] in
            self?.invalidateAll()
        }
    }

    // MARK: - Public

    func cachedHistory(userId: Int, allowStale: Bool = false) -> [UserHistoryEntry]? {
        allowStale ? cache.getStale(userId) : cache.get(userId)
    }

    /// First page of history. On a cache hit returns instantly; on a miss
    /// performs a network request and stores it in cache + on disk.
    func history(
        configuration: ShikimoriConfiguration,
        userId: Int,
        forceRefresh: Bool = false
    ) async throws -> [UserHistoryEntry] {
        if !forceRefresh, let cached = cache.get(userId) {
            NetworkLogStore.shared.logUIEvent("history_repo_hit user=\(userId) count=\(cached.count)")
            return cached
        }
        if let existing = pending[userId] { return try await existing.value }

        let task = Task<[UserHistoryEntry], Error> { [weak self] in
            defer { self?.pending.removeValue(forKey: userId) }
            let rest = ShikimoriRESTClient(configuration: configuration)
            let entries = try await rest.userHistory(
                id: userId,
                targetType: "Anime",
                limit: Self.firstPageLimit,
                page: 1
            )
            self?.cache.set(entries, for: userId)
            if let strongSelf = self {
                DiskBackup.save(cache: strongSelf.cache, filename: Self.diskFilename)
            }
            NetworkLogStore.shared.logUIEvent(
                "history_repo_loaded user=\(userId) count=\(entries.count)"
            )
            return entries
        }
        pending[userId] = task
        return try await task.value
    }

    /// Load-more. Not cached (pagination is always fresh — the UI appends to
    /// the first page). Returns an empty array if the page is out of bounds.
    func historyPage(
        configuration: ShikimoriConfiguration,
        userId: Int,
        page: Int,
        limit: Int = firstPageLimit
    ) async throws -> [UserHistoryEntry] {
        let rest = ShikimoriRESTClient(configuration: configuration)
        let entries = try await rest.userHistory(
            id: userId,
            targetType: "Anime",
            limit: limit,
            page: page
        )
        NetworkLogStore.shared.logUIEvent(
            "history_repo_page user=\(userId) page=\(page) count=\(entries.count)"
        )
        return entries
    }

    // MARK: - Invalidation

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
}
