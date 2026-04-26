//
//  LibraryLoader.swift
//  MyShikiPlayer
//
//  Owns the "fetch the user's whole library" pipeline: paginate
//  `/user_rates`, hydrate via Shikimori GraphQL in chunks, map into
//  `AnimeListViewModel.Item`s. Per-page and per-chunk retries live
//  inside via `RetryPolicy.withRateLimitRetry` — wrapping the whole
//  pipeline in another retry would multiply attempts and re-fetch
//  already-loaded chunks.
//
//  Stateless — `AnimeListViewModel` keeps every `@Published` field
//  intact and just delegates the heavy work here.
//

import Foundation

@MainActor
struct LibraryLoader {
    /// Filter state needed to hydrate the GraphQL queries with the same
    /// kind/rating/season/search the user picked.
    struct FilterCriteria {
        let selectedKind: String
        let selectedRating: String
        let selectedSeason: String
        let searchText: String
    }

    /// Result of one full reload — handed back to the VM to assign.
    struct LoadResult {
        let items: [AnimeListViewModel.Item]
    }

    private let rest: ShikimoriRESTClient
    private let graphql: ShikimoriGraphQLClient

    init(configuration: ShikimoriConfiguration) {
        self.rest = ShikimoriRESTClient(configuration: configuration)
        self.graphql = ShikimoriGraphQLClient(configuration: configuration)
    }

    func reload(userId: Int, criteria: FilterCriteria) async throws -> LoadResult {
        let rates = try await fetchAllRates(userId: userId)
        let animeById = try await fetchAnimeMap(
            ids: Array(Set(rates.map(\.targetId))).sorted(),
            criteria: criteria
        )
        let items: [AnimeListViewModel.Item] = rates.compactMap { rate in
            let anime = animeById[rate.targetId]
            let title = anime?.russian?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? anime?.russian ?? ""
                : (anime?.name ?? "Anime #\(rate.targetId)")
            let kind = (anime?.kind ?? "").uppercased()
            let year = Self.extractYear(from: anime?.releasedOn?.date ?? anime?.airedOn?.date)
            return AnimeListViewModel.Item(
                id: rate.id,
                shikimoriId: rate.targetId,
                title: title,
                kind: kind.isEmpty ? "ANIME" : kind,
                year: year,
                status: rate.status,
                score: rate.score,
                episodesWatched: rate.episodes,
                posterURL: anime.flatMap(Self.posterURL(from:)),
                updatedAt: rate.updatedAt,
                animeStatus: anime?.status?.lowercased(),
                animeSeason: anime?.season
            )
        }
        .sorted { $0.updatedAt > $1.updatedAt }
        return LoadResult(items: items)
    }

    /// Update a single rate via REST and return the freshly-decoded record.
    /// Keeps the per-call retry inside the loader (was inline in the VM).
    func updateRate(id: Int, body: UserRateV2UpdateBody) async throws -> UserRateV2 {
        try await Self.withRetry {
            try await self.rest.updateUserRate(id: id, body: body)
        }
    }

    // MARK: - Internal pagination

    private func fetchAllRates(userId: Int) async throws -> [UserRateV2] {
        try await fetchAllRatesForStatus(userId: userId, status: nil)
    }

    private func fetchAllRatesForStatus(userId: Int, status: String?) async throws -> [UserRateV2] {
        var page = 1
        let limit = 100
        let maxPages = 300
        var result: [UserRateV2] = []
        var seenRateIds = Set<Int>()

        while page <= maxPages {
            var query = UserRatesListQuery()
            query.userId = userId
            query.targetType = "Anime"
            query.status = status
            query.page = page
            query.limit = limit
            // Retry per-page so a single 429/5xx does not blow up the whole list.
            let chunk = try await Self.withRetry {
                try await self.rest.userRates(query: query)
            }

            guard !chunk.isEmpty else { break }

            // Defensive pagination: stop if API starts repeating pages.
            var appendedCount = 0
            for rate in chunk where !seenRateIds.contains(rate.id) {
                seenRateIds.insert(rate.id)
                result.append(rate)
                appendedCount += 1
            }
            if appendedCount == 0 { break }
            // Shikimori currently ignores `limit` on `/user_rates` and returns
            // every record on page=1. If the server returned more than asked,
            // pagination is either disabled or broken — going further would
            // re-fetch the same payload.
            if chunk.count > limit { break }
            if chunk.count < limit { break }

            page += 1
        }
        return result
    }

    private func fetchAnimeMap(
        ids: [Int],
        criteria: FilterCriteria
    ) async throws -> [Int: GraphQLAnimeSummary] {
        guard !ids.isEmpty else { return [:] }
        var map: [Int: GraphQLAnimeSummary] = [:]
        let trimmedSearch = criteria.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSeason = criteria.selectedSeason.trimmingCharacters(in: .whitespacesAndNewlines)
        for chunk in ids.chunkedForLibrary(size: 40) {
            // Retry per-chunk: a 429 on chunk N must not throw away the
            // already-fetched chunks 1…N-1.
            let animes = try await Self.withRetry {
                try await self.graphql.animesByIdsDynamic(
                    ids: chunk,
                    search: trimmedSearch.isEmpty ? nil : trimmedSearch,
                    kindRaw: criteria.selectedKind == "ALL" ? nil : criteria.selectedKind,
                    ratingRaw: criteria.selectedRating == "ALL" ? nil : criteria.selectedRating,
                    season: trimmedSeason.isEmpty ? nil : trimmedSeason
                )
            }
            for anime in animes {
                map[anime.id] = anime
            }
        }
        return map
    }

    // MARK: - Static helpers

    private static func extractYear(from dateString: String?) -> String {
        guard let dateString, dateString.count >= 4 else { return "—" }
        return String(dateString.prefix(4))
    }

    private static func posterURL(from anime: GraphQLAnimeSummary) -> URL? {
        let path = anime.poster?.mainUrl ?? anime.poster?.originalUrl
        guard let path, !path.isEmpty else { return nil }
        return URL(string: path)
    }

    /// Thin wrapper kept for call-site readability. All retry logic lives in
    /// `RetryPolicy.withRateLimitRetry` so the schedule is uniform across
    /// repositories. We pass `isTransient` to keep the previous broader net
    /// (429, 5xx, 522, common URLError drops) — Shikimori-only call-sites use
    /// the default `isRateLimited` predicate instead.
    static func withRetry<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        try await RetryPolicy.withRateLimitRetry(
            delays: RetryPolicy.exponentialBackoff,
            shouldRetry: RetryPolicy.isTransient
        ) {
            try await operation()
        }
    }
}

private extension Array {
    func chunkedForLibrary(size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var idx = startIndex
        while idx < endIndex {
            let end = index(idx, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(Array(self[idx..<end]))
            idx = end
        }
        return chunks
    }
}
