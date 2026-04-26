//
//  ProfileRepo.swift
//  MyShikiPlayer
//
//  Profile cache: profile + favorites by userId. TTL 10 minutes — stats
//  shift after each userRate change, so there is no point in caching
//  aggressively.
//

import Foundation

@MainActor
final class ProfileRepo {
    static let shared = ProfileRepo()

    private static let diskFilename = "profile.json"

    private init() {
        let loaded = DiskBackup.load(into: cache, filename: Self.diskFilename)
        if loaded > 0 {
            NetworkLogStore.shared.logUIEvent("profile_repo_disk_loaded users=\(loaded)")
        }
        subscribeToCacheEvents()
    }

    struct Snapshot: Equatable, Codable {
        let profile: UserProfile
        let favourites: [UserFavouriteAnime]
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
            // The favourites endpoint returns image as a single string —
            // often `missing_*`. Ask PosterEnricher to pull real posters by id.
            let missingIds = rawFavs
                .filter { ($0.image ?? "").isEmpty || ($0.image ?? "").contains("missing_") }
                .map(\.id)
            if !missingIds.isEmpty {
                await PosterEnricher.shared.enrich(configuration: configuration, ids: missingIds)
            }
            let enrichedFavs = rawFavs.map { fav -> UserFavouriteAnime in
                guard let enriched = PosterEnricher.shared.cachedURL(id: fav.id) else { return fav }
                return UserFavouriteAnime(
                    id: fav.id,
                    name: fav.name,
                    russian: fav.russian,
                    image: enriched,
                    url: fav.url
                )
            }
            let snap = try Snapshot(
                profile: await profile,
                favourites: enrichedFavs
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
