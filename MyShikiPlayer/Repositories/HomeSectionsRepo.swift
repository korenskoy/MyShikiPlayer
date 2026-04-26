//
//  HomeSectionsRepo.swift
//  MyShikiPlayer
//
//  Cache for the five home blocks (hero + trending + newEpisodes +
//  recommendations + continueWatching). TTL 20 minutes per-userId.
//
//  Enrichment strategy: REST sections run in parallel, but GraphQL is a
//  SINGLE request for all missing posters + all targetIds from
//  continueWatching. Previously there were 4 parallel GraphQL requests →
//  rate-limit 429. Now it is a single request with retry on 429.
//

import Foundation

@MainActor
final class HomeSectionsRepo {
    static let shared = HomeSectionsRepo()

    private static let diskFilename = "home-sections.json"

    private init() {
        let loaded = DiskBackup.load(into: cache, filename: Self.diskFilename)
        if loaded > 0 {
            NetworkLogStore.shared.logUIEvent("home_repo_disk_loaded users=\(loaded)")
        }
        // user-rate / favorite — invalidate by userId ("Continue watching"
        // and trending depend on user-state).
        CacheEvents.observeAnimeMutation { [weak self] _, userId in
            self?.invalidate(userId: userId)
        }
        CacheEvents.observeClearAll { [weak self] in
            self?.invalidateAll()
        }
    }

    struct Snapshot: Codable {
        let featuredHero: AnimeListItem?
        let trending: [AnimeListItem]
        let newEpisodes: [AnimeListItem]
        let recommendations: [AnimeListItem]
        let continueWatching: [HomeContinueItem]
    }

    private let cache = TTLCache<String, Snapshot>(ttl: 20 * 60)
    private var pending: [String: Task<Snapshot, Error>] = [:]

    private func key(userId: Int?) -> String { userId.map(String.init) ?? "anon" }

    func cachedSnapshot(userId: Int?, allowStale: Bool = false) -> Snapshot? {
        let k = key(userId: userId)
        return allowStale ? cache.getStale(k) : cache.get(k)
    }

    func snapshot(
        configuration: ShikimoriConfiguration,
        userId: Int?,
        forceRefresh: Bool = false
    ) async throws -> Snapshot {
        let key = self.key(userId: userId)
        if !forceRefresh, let cached = cache.get(key) {
            NetworkLogStore.shared.logUIEvent("home_repo_hit user=\(key)")
            return cached
        }
        if let existing = pending[key] { return try await existing.value }

        let task = Task<Snapshot, Error> { [weak self] in
            defer { self?.pending.removeValue(forKey: key) }

            // Step 1: REST (all in parallel — they are fast and not rate-limited).
            async let trendingRaw = Self.fetchSectionRaw(
                configuration,
                query: Self.trendingQuery(),
                label: "trending"
            )
            async let newEpisodesRaw = Self.fetchSectionRaw(
                configuration,
                query: Self.newEpisodesQuery(),
                label: "new_episodes"
            )
            async let recommendationsRaw = Self.fetchSectionRaw(
                configuration,
                query: Self.recommendationsQuery(),
                label: "recommendations"
            )
            async let ratesResult = Self.fetchRates(configuration, userId: userId)

            let t = await trendingRaw
            let n = await newEpisodesRaw
            let r = await recommendationsRaw
            let rates = await ratesResult

            // Step 2: collect every ID that needs GraphQL (posters + continue).
            let missingFromSections = (t + n + r)
                .filter { Self.needsPosterEnrichment($0) }
                .map(\.id)
            let rateIds: [Int]
            let continueFailed: Bool
            switch rates {
            case .success(let list):
                rateIds = list.map(\.targetId)
                continueFailed = false
            case .failure:
                rateIds = []
                continueFailed = true
            }
            let allIds = Array(Set(missingFromSections + rateIds))

            // Step 3: SINGLE GraphQL request with retry on 429.
            let summariesById = await Self.fetchSummaries(configuration, ids: allIds)

            // Step 4: apply enrichment + build continue.
            let tEnriched = Self.applyPosters(to: t, summaries: summariesById, label: "trending")
            let nEnriched = Self.applyPosters(to: n, summaries: summariesById, label: "new_episodes")
            let rEnriched = Self.applyPosters(to: r, summaries: summariesById, label: "recommendations")

            let continueItems: [HomeContinueItem]
            if case .success(let list) = rates {
                continueItems = Self.buildContinueItems(rates: list, summaries: summariesById)
            } else {
                continueItems = []
            }

            let snap = Snapshot(
                featuredHero: tEnriched.first,
                trending: tEnriched,
                newEpisodes: nEnriched,
                recommendations: rEnriched,
                continueWatching: continueItems
            )
            // Do not cache if continue failed: on the next tab-switch we
            // should retry the request, not show empty for 20 minutes.
            // Also do not cache if trending is empty — likely a network failure.
            let shouldCache = !continueFailed && !tEnriched.isEmpty
            if shouldCache {
                self?.cache.set(snap, for: key)
                // Write to disk — on the next cold start Home appears instantly.
                if let strongSelf = self {
                    DiskBackup.save(cache: strongSelf.cache, filename: Self.diskFilename)
                }
            }
            NetworkLogStore.shared.logUIEvent(
                "home_repo_loaded user=\(key) trending=\(tEnriched.count) new=\(nEnriched.count) " +
                "reco=\(rEnriched.count) cw=\(continueItems.count) cw_ok=\(!continueFailed) " +
                "cached=\(shouldCache) summaries=\(summariesById.count)"
            )
            return snap
        }
        pending[key] = task
        return try await task.value
    }

    func invalidate(userId: Int?) {
        cache.invalidate(key(userId: userId))
        if let task = pending[key(userId: userId)] {
            task.cancel()
            pending.removeValue(forKey: key(userId: userId))
        }
    }

    func invalidateAll() {
        cache.invalidateAll()
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        DiskBackup.remove(filename: Self.diskFilename)
    }

    // MARK: - Queries

    private static func trendingQuery() -> AnimeListQuery {
        var q = AnimeListQuery()
        q.status = "ongoing"
        q.order = "popularity"
        q.limit = 6
        return q
    }

    private static func newEpisodesQuery() -> AnimeListQuery {
        var q = AnimeListQuery()
        q.status = "ongoing"
        q.order = "aired_on"
        q.limit = 6
        return q
    }

    private static func recommendationsQuery() -> AnimeListQuery {
        var q = AnimeListQuery()
        q.order = "ranked"
        q.limit = 5
        return q
    }

    // MARK: - REST loaders

    private static func fetchSectionRaw(
        _ config: ShikimoriConfiguration,
        query: AnimeListQuery,
        label: String
    ) async -> [AnimeListItem] {
        let rest = ShikimoriRESTClient(configuration: config)
        do {
            return try await rest.animes(query: query)
        } catch {
            await MainActor.run {
                NetworkLogStore.shared.logAppError(
                    "home_repo_section_failed \(label) \(error.localizedDescription)"
                )
            }
            return []
        }
    }

    private static func fetchRates(
        _ config: ShikimoriConfiguration,
        userId: Int?
    ) async -> Result<[UserRateV2], Error> {
        guard let userId else { return .success([]) }
        let rest = ShikimoriRESTClient(configuration: config)
        var q = UserRatesListQuery()
        q.userId = userId
        q.status = "watching"
        q.limit = 8
        do {
            let rates = try await rest.userRates(query: q)
            let sorted = rates.sorted { $0.updatedAt > $1.updatedAt }
            return .success(Array(sorted.prefix(4)))
        } catch {
            await MainActor.run {
                NetworkLogStore.shared.logAppError(
                    "home_repo_continue_rates_failed \(error.localizedDescription)"
                )
            }
            return .failure(error)
        }
    }

    // MARK: - Single GraphQL with retry on 429

    /// Single GraphQL fetch over all IDs with exponential backoff on 429.
    /// Returns id → summary map; empty dict means all attempts failed.
    private static func fetchSummaries(
        _ config: ShikimoriConfiguration,
        ids: [Int]
    ) async -> [Int: GraphQLAnimeSummary] {
        guard !ids.isEmpty else { return [:] }
        let gql = ShikimoriGraphQLClient(configuration: config)
        var retryCount = 0
        do {
            let summaries = try await RetryPolicy.withRateLimitRetry(
                onRetry: { attempt, willRetry in
                    retryCount = attempt + 1
                    await MainActor.run {
                        NetworkLogStore.shared.logUIEvent(
                            "home_enrich_429 attempt=\(attempt) will_retry=\(willRetry)"
                        )
                    }
                }
            ) {
                try await gql.animes(ids: ids, limit: ids.count)
            }
            if retryCount > 0 {
                await MainActor.run {
                    NetworkLogStore.shared.logUIEvent(
                        "home_enrich_retry_success attempt=\(retryCount) got=\(summaries.count)"
                    )
                }
            }
            return Dictionary(uniqueKeysWithValues: summaries.map { ($0.id, $0) })
        } catch {
            await MainActor.run {
                NetworkLogStore.shared.logAppError(
                    "home_enrich_summaries_failed ids=\(ids.count) " +
                    "err=\(error.localizedDescription)"
                )
            }
            return [:]
        }
    }

    // MARK: - Enrichment + continue builder

    private static func applyPosters(
        to items: [AnimeListItem],
        summaries: [Int: GraphQLAnimeSummary],
        label: String
    ) -> [AnimeListItem] {
        var resolved = 0
        let result = items.map { item -> AnimeListItem in
            guard needsPosterEnrichment(item) else { return item }
            guard let summary = summaries[item.id] else { return item }
            let candidates = [summary.poster?.originalUrl, summary.poster?.mainUrl]
            for raw in candidates {
                guard let raw, !raw.isEmpty, !raw.contains("missing_") else { continue }
                resolved += 1
                return AnimeListItem(
                    id: item.id,
                    name: item.name,
                    russian: item.russian,
                    image: AnimeImageURLs(original: raw, preview: raw, x96: nil, x48: nil),
                    url: item.url,
                    kind: item.kind,
                    score: item.score,
                    status: item.status,
                    episodes: item.episodes,
                    episodesAired: item.episodesAired,
                    airedOn: item.airedOn,
                    releasedOn: item.releasedOn
                )
            }
            return item
        }
        let missingCount = items.filter { needsPosterEnrichment($0) }.count
        if missingCount > 0 {
            NetworkLogStore.shared.logUIEvent(
                "home_enrich \(label) missing=\(missingCount) resolved=\(resolved)"
            )
        }
        return result
    }

    private static func buildContinueItems(
        rates: [UserRateV2],
        summaries: [Int: GraphQLAnimeSummary]
    ) -> [HomeContinueItem] {
        rates.compactMap { rate in
            guard let summary = summaries[rate.targetId] else { return nil }
            let listItem = AnimeListItem(
                id: summary.id,
                name: summary.name ?? "—",
                russian: summary.russian,
                image: AnimeImageURLs(
                    original: summary.poster?.originalUrl,
                    preview: summary.poster?.mainUrl ?? summary.poster?.originalUrl,
                    x96: nil,
                    x48: nil
                ),
                url: summary.url,
                kind: summary.kind,
                score: summary.score.map { String($0) },
                status: summary.status,
                episodes: summary.episodes,
                episodesAired: summary.episodesAired,
                airedOn: summary.airedOn?.date,
                releasedOn: summary.releasedOn?.date
            )
            return HomeContinueItem(
                id: rate.targetId,
                anime: listItem,
                episodesWatched: rate.episodes,
                episodesAired: summary.episodesAired,
                totalEpisodes: summary.episodes,
                note: formatRelativeDate(rate.updatedAt)
            )
        }
    }

    private static func needsPosterEnrichment(_ item: AnimeListItem) -> Bool {
        let raw = item.image?.preview
            ?? item.image?.original
            ?? item.image?.x96
            ?? item.image?.x48
            ?? ""
        return raw.isEmpty || raw.contains("missing_")
    }

    private static func formatRelativeDate(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.unitsStyle = .short
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}
