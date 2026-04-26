//
//  PosterEnricher.swift
//  MyShikiPlayer
//
//  For many titles Shikimori REST returns `missing_preview.jpg` — a
//  placeholder, even though GraphQL has the real poster. This service
//  batches "give me posters for these ids" into one GraphQL request with
//  retry on 429, and keeps an id→poster URL cache (1 hour TTL).
//
//  Used by catalog, calendar, "Similar" in details, favorites — anywhere
//  REST returns a placeholder.
//

import Foundation

@MainActor
final class PosterEnricher {
    static let shared = PosterEnricher()

    private static let diskFilename = "poster-enricher.json"

    private init() {
        let loaded = DiskBackup.load(into: cache, filename: Self.diskFilename)
        if loaded > 0 {
            NetworkLogStore.shared.logUIEvent("poster_enricher_disk_loaded count=\(loaded)")
        }
        // Posters are independent of user-state — only listen for wipe.
        CacheEvents.observeClearAll { [weak self] in
            self?.invalidateAll()
        }
    }

    /// id → real poster URL cache. 1 hour — posters do not change often.
    private let cache = TTLCache<Int, String>(ttl: 60 * 60)
    /// Active request (batch). Request dedup: concurrent enrich() calls wait.
    private var pending: Task<Void, Never>?

    /// Synchronous read: if a cached URL exists — return it, otherwise nil.
    /// `allowStale: true` — also returns expired entries (for immediate render).
    func cachedURL(id: Int, allowStale: Bool = true) -> String? {
        allowStale ? cache.getStale(id) : cache.get(id)
    }

    /// Asynchronously populates the cache with posters for the given ids.
    /// Idempotent: ids already in cache are skipped.
    /// Non-throwing — errors are logged, the caller proceeds.
    func enrich(configuration: ShikimoriConfiguration, ids: [Int]) async {
        let missing = Array(Set(ids.filter { cache.getStale($0) == nil }))
        guard !missing.isEmpty else { return }

        if let existing = pending {
            // Wait for the current batch (in case it already covers our ids).
            _ = await existing.value
            // After it completes — check what is still left to do.
            let stillMissing = missing.filter { cache.getStale($0) == nil }
            guard !stillMissing.isEmpty else { return }
            await runBatch(configuration: configuration, ids: stillMissing)
            return
        }

        await runBatch(configuration: configuration, ids: missing)
    }

    /// Enriches a list of AnimeListItem-s: for items with a placeholder
    /// poster whose real URL is now in the cache — swaps `image`. Other
    /// fields are untouched.
    func enriched(
        configuration: ShikimoriConfiguration,
        items: [AnimeListItem]
    ) async -> [AnimeListItem] {
        let missingIds = items.filter(\.needsPosterEnrichment).map(\.id)
        if !missingIds.isEmpty {
            await enrich(configuration: configuration, ids: missingIds)
        }
        return items.map { item in
            guard item.needsPosterEnrichment, let url = cachedURL(id: item.id) else { return item }
            return item.withPoster(url: url)
        }
    }

    func invalidateAll() {
        cache.invalidateAll()
        pending?.cancel()
        pending = nil
        DiskBackup.remove(filename: Self.diskFilename)
    }

    // MARK: - Private

    private func runBatch(configuration: ShikimoriConfiguration, ids: [Int]) async {
        let task = Task<Void, Never> { [weak self] in
            defer { self?.pending = nil }
            guard let self else { return }
            let gql = ShikimoriGraphQLClient(configuration: configuration)
            let summaries = await Self.fetchWithRetry(gql: gql, ids: ids)
            for summary in summaries {
                if let url = Self.preferredPoster(summary.poster) {
                    self.cache.set(url, for: summary.id)
                }
            }
            NetworkLogStore.shared.logUIEvent(
                "poster_enricher_batch requested=\(ids.count) received=\(summaries.count)"
            )
            // Persist the updated cache to disk — it will survive cold start.
            DiskBackup.save(cache: self.cache, filename: Self.diskFilename)
        }
        pending = task
        _ = await task.value
    }

    private static func fetchWithRetry(
        gql: ShikimoriGraphQLClient,
        ids: [Int]
    ) async -> [GraphQLAnimeSummary] {
        do {
            return try await RetryPolicy.withRateLimitRetry(
                onRetry: { attempt, willRetry in
                    await MainActor.run {
                        NetworkLogStore.shared.logUIEvent(
                            "poster_enricher_429 attempt=\(attempt) will_retry=\(willRetry)"
                        )
                    }
                }
            ) {
                try await gql.animes(ids: ids, limit: ids.count)
            }
        } catch {
            await MainActor.run {
                NetworkLogStore.shared.logAppError(
                    "poster_enricher_failed ids=\(ids.count) err=\(error.localizedDescription)"
                )
            }
            return []
        }
    }

    private static func preferredPoster(_ poster: GraphQLPoster?) -> String? {
        let candidates = [poster?.originalUrl, poster?.mainUrl]
        for raw in candidates {
            guard let raw, !raw.isEmpty, !raw.contains("missing_") else { continue }
            return raw
        }
        return nil
    }
}

// MARK: - AnimeListItem helpers

extension AnimeListItem {
    /// True if REST returned missing_*.jpg or an empty string.
    var needsPosterEnrichment: Bool {
        let raw = image?.preview
            ?? image?.original
            ?? image?.x96
            ?? image?.x48
            ?? ""
        return raw.isEmpty || raw.contains("missing_")
    }

    /// Returns a copy with the poster replaced across all image fields.
    func withPoster(url: String) -> AnimeListItem {
        AnimeListItem(
            id: id,
            name: name,
            russian: russian,
            image: AnimeImageURLs(original: url, preview: url, x96: nil, x48: nil),
            url: self.url,
            kind: kind,
            score: score,
            status: status,
            episodes: episodes,
            episodesAired: episodesAired,
            airedOn: airedOn,
            releasedOn: releasedOn
        )
    }
}
