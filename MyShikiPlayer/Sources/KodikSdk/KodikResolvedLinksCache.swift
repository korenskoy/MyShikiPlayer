//
//  KodikResolvedLinksCache.swift
//  MyShikiPlayer
//
//  In-memory cache for resolved Kodik episode links keyed by the raw
//  episodeLink string (e.g. "//kodikplayer.com/seria/<id>/<hash>/720p").
//  Resolving a single link costs two HTTP round-trips — for a user
//  flipping between dub studios in the player the cache makes repeated
//  picks instant.
//
//  Lifetime: process-only (no disk backup). TTL is short on purpose —
//  Kodik occasionally rotates the encrypted segment URLs, and a stale
//  hit here would 404 the playlist. The catalog itself lives in
//  `KodikCatalogRepo`.
//

import Foundation

@MainActor
final class KodikResolvedLinksCache {
    static let shared = KodikResolvedLinksCache()

    private let cache = TTLCache<String, [KodikVideoLinksResolver.ResolvedLink]>(ttl: 5 * 60)

    private init() {
        CacheEvents.observeClearAll { [weak self] in
            self?.cache.invalidateAll()
        }
    }

    func cached(for episodeLink: String) -> [KodikVideoLinksResolver.ResolvedLink]? {
        cache.get(episodeLink)
    }

    func store(_ links: [KodikVideoLinksResolver.ResolvedLink], for episodeLink: String) {
        cache.set(links, for: episodeLink)
    }

    func invalidateAll() {
        cache.invalidateAll()
    }
}
