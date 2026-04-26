//
//  AnimeFilterViewModel.swift
//  MyShikiPlayer
//

import Foundation
import Combine

/// Holds user-selected filter facets. Builds an `AnimeListQuery` for the catalog endpoint
/// and exposes individual fields for client-side filtering against cached items.
@MainActor
final class AnimeFilterViewModel: ObservableObject {
    private enum PersistedKey {
        static let prefix = "animeFilter.v1."
        static func forScope(_ scope: String) -> String { prefix + scope }
    }

    let scope: String

    @Published var selectedKinds: Set<AnimeKind>
    @Published var selectedStatuses: Set<AnimeStatus>
    @Published var selectedRatings: Set<AnimeRating>
    @Published var selectedDurations: Set<AnimeDuration>
    @Published var selectedSeasons: Set<AnimeSeasonPreset>
    /// Specific years (2024, 2023, …) — Shikimori accepts a 4-digit year
    /// in the same `season` query param as the quarterly presets. We keep
    /// them separate to avoid inflating the enum with one case per year.
    @Published var selectedYears: Set<Int>
    @Published var selectedOrigins: Set<AnimeOrigin>
    @Published var selectedGenreIds: Set<Int>
    @Published var selectedStudioIds: Set<Int>
    @Published var selectedMyListStatuses: Set<MyListStatus>
    @Published var selectedOrder: AnimeOrder?
    @Published var licensedOnly: Bool
    @Published var excludeCensored: Bool
    @Published var minScore: Int?
    @Published var searchText: String

    private var subscriptions: Set<AnyCancellable> = []

    init(scope: String = "default") {
        self.scope = scope
        let persisted = Self.loadPersisted(scope: scope)

        selectedKinds = persisted.kinds
        selectedStatuses = persisted.statuses
        selectedRatings = persisted.ratings
        selectedDurations = persisted.durations
        selectedSeasons = persisted.seasons
        selectedYears = persisted.years
        selectedOrigins = persisted.origins
        selectedGenreIds = persisted.genreIds
        selectedStudioIds = persisted.studioIds
        selectedMyListStatuses = persisted.mylistStatuses
        selectedOrder = persisted.order
        licensedOnly = persisted.licensedOnly
        excludeCensored = persisted.excludeCensored
        minScore = persisted.minScore
        searchText = persisted.searchText

        observeChanges()
    }

    // MARK: - Public API

    /// Builds an `AnimeListQuery` suitable for `GET /api/animes`.
    /// Multi-selection is comma-joined; Shikimori supports that for kind/status/rating/season/duration/genre/studio/mylist/origin.
    func buildQuery(limit: Int = 50, page: Int = 1) -> AnimeListQuery {
        var query = AnimeListQuery()
        query.page = page
        query.limit = limit

        if !selectedKinds.isEmpty {
            query.kind = selectedKinds.map(\.rawValue).sorted().joined(separator: ",")
        }
        if !selectedStatuses.isEmpty {
            query.status = selectedStatuses.map(\.rawValue).sorted().joined(separator: ",")
        }
        if !selectedRatings.isEmpty {
            query.rating = selectedRatings.map(\.rawValue).sorted().joined(separator: ",")
        }
        if !selectedDurations.isEmpty {
            query.duration = selectedDurations.map(\.rawValue).sorted().joined(separator: ",")
        }
        // Shikimori's season param is universal: it accepts a comma-separated
        // mix of quarterly presets, years, ranges and decades.
        var seasonTokens: [String] = []
        seasonTokens.append(contentsOf: selectedSeasons.map(\.rawValue))
        seasonTokens.append(contentsOf: selectedYears.map(String.init))
        if !seasonTokens.isEmpty {
            query.season = seasonTokens.sorted().joined(separator: ",")
        }
        if !selectedOrigins.isEmpty {
            query.origin = selectedOrigins.map(\.rawValue).sorted().joined(separator: ",")
        }
        if !selectedGenreIds.isEmpty {
            query.genreV2 = selectedGenreIds.sorted().map(String.init).joined(separator: ",")
        }
        if !selectedStudioIds.isEmpty {
            query.studio = selectedStudioIds.sorted().map(String.init).joined(separator: ",")
        }
        if !selectedMyListStatuses.isEmpty {
            query.mylist = selectedMyListStatuses.map(\.rawValue).sorted().joined(separator: ",")
        }
        if let selectedOrder {
            query.order = selectedOrder.rawValue
        }
        if licensedOnly { query.licensed = true }
        if excludeCensored { query.censored = false }
        if let minScore, minScore > 0 { query.score = minScore }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty { query.search = trimmedSearch }

        return query
    }

    /// Returns true when the facet set is empty (i.e. no filters applied).
    var isEmpty: Bool {
        selectedKinds.isEmpty &&
        selectedStatuses.isEmpty &&
        selectedRatings.isEmpty &&
        selectedDurations.isEmpty &&
        selectedSeasons.isEmpty &&
        selectedYears.isEmpty &&
        selectedOrigins.isEmpty &&
        selectedGenreIds.isEmpty &&
        selectedStudioIds.isEmpty &&
        selectedMyListStatuses.isEmpty &&
        selectedOrder == nil &&
        !licensedOnly &&
        !excludeCensored &&
        (minScore ?? 0) == 0 &&
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Total number of active facets (used for badge count in UI).
    var activeFacetCount: Int {
        var count = 0
        count += selectedKinds.count
        count += selectedStatuses.count
        count += selectedRatings.count
        count += selectedDurations.count
        count += selectedSeasons.count
        count += selectedYears.count
        count += selectedOrigins.count
        count += selectedGenreIds.count
        count += selectedStudioIds.count
        count += selectedMyListStatuses.count
        if selectedOrder != nil { count += 1 }
        if licensedOnly { count += 1 }
        if excludeCensored { count += 1 }
        if (minScore ?? 0) > 0 { count += 1 }
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        return count
    }

    func reset() {
        selectedKinds = []
        selectedStatuses = []
        selectedRatings = []
        selectedDurations = []
        selectedSeasons = []
        selectedYears = []
        selectedOrigins = []
        selectedGenreIds = []
        selectedStudioIds = []
        selectedMyListStatuses = []
        selectedOrder = nil
        licensedOnly = false
        excludeCensored = false
        minScore = nil
        searchText = ""
    }

    // MARK: - Toggling helpers

    func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    /// Applies the filter to a list of GraphQL anime summaries in-memory (used by user-list mode).
    func applyClientSide<Summary>(to items: [Summary], summary: (Summary) -> FilterableAnime?) -> [Summary] {
        items.filter { item in
            guard let anime = summary(item) else { return true }
            return matchesClientSide(anime)
        }
    }

    private func matchesClientSide(_ anime: FilterableAnime) -> Bool {
        if !selectedKinds.isEmpty {
            guard let raw = anime.kind, let k = AnimeKind(rawValue: raw), selectedKinds.contains(k) else { return false }
        }
        if !selectedStatuses.isEmpty {
            guard let raw = anime.status, let s = AnimeStatus(rawValue: raw), selectedStatuses.contains(s) else { return false }
        }
        if !selectedRatings.isEmpty {
            guard let raw = anime.rating, let r = AnimeRating(rawValue: raw), selectedRatings.contains(r) else { return false }
        }
        if !selectedDurations.isEmpty {
            guard let minutes = anime.durationMinutes else { return false }
            let bucket: AnimeDuration = minutes < 10 ? .short : (minutes <= 30 ? .medium : .long)
            if !selectedDurations.contains(bucket) { return false }
        }
        if !selectedOrigins.isEmpty {
            guard let raw = anime.origin, let o = AnimeOrigin(rawValue: raw), selectedOrigins.contains(o) else { return false }
        }
        if !selectedGenreIds.isEmpty {
            let ids = Set(anime.genreIds)
            if ids.isDisjoint(with: selectedGenreIds) { return false }
        }
        if !selectedStudioIds.isEmpty {
            let ids = Set(anime.studioIds)
            if ids.isDisjoint(with: selectedStudioIds) { return false }
        }
        if let minScore, minScore > 0 {
            let score = Int(anime.score ?? 0)
            if score < minScore { return false }
        }
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmedSearch.isEmpty {
            let haystack = [anime.title, anime.titleRussian, anime.titleEnglish]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            if !haystack.contains(trimmedSearch) { return false }
        }
        return true
    }

    // MARK: - Persistence

    private func observeChanges() {
        objectWillChange
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.persist()
            }
            .store(in: &subscriptions)
    }

    private func persist() {
        let snapshot = Snapshot(
            kinds: selectedKinds.map(\.rawValue),
            statuses: selectedStatuses.map(\.rawValue),
            ratings: selectedRatings.map(\.rawValue),
            durations: selectedDurations.map(\.rawValue),
            seasons: selectedSeasons.map(\.rawValue),
            years: Array(selectedYears),
            origins: selectedOrigins.map(\.rawValue),
            genreIds: Array(selectedGenreIds),
            studioIds: Array(selectedStudioIds),
            mylistStatuses: selectedMyListStatuses.map(\.rawValue),
            order: selectedOrder?.rawValue,
            licensedOnly: licensedOnly,
            excludeCensored: excludeCensored,
            minScore: minScore,
            searchText: searchText
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: PersistedKey.forScope(scope))
    }

    private static func loadPersisted(scope: String) -> LoadedState {
        guard let data = UserDefaults.standard.data(forKey: PersistedKey.forScope(scope)),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return LoadedState()
        }
        return LoadedState(
            kinds: Set(snap.kinds.compactMap(AnimeKind.init(rawValue:))),
            statuses: Set(snap.statuses.compactMap(AnimeStatus.init(rawValue:))),
            ratings: Set(snap.ratings.compactMap(AnimeRating.init(rawValue:))),
            durations: Set(snap.durations.compactMap(AnimeDuration.init(rawValue:))),
            seasons: Set(snap.seasons.compactMap(AnimeSeasonPreset.init(rawValue:))),
            years: Set(snap.years ?? []),
            origins: Set(snap.origins.compactMap(AnimeOrigin.init(rawValue:))),
            genreIds: Set(snap.genreIds),
            studioIds: Set(snap.studioIds),
            mylistStatuses: Set(snap.mylistStatuses.compactMap(MyListStatus.init(rawValue:))),
            order: snap.order.flatMap(AnimeOrder.init(rawValue:)),
            licensedOnly: snap.licensedOnly,
            excludeCensored: snap.excludeCensored,
            minScore: snap.minScore,
            searchText: snap.searchText
        )
    }

    private struct LoadedState {
        var kinds: Set<AnimeKind> = []
        var statuses: Set<AnimeStatus> = []
        var ratings: Set<AnimeRating> = []
        var durations: Set<AnimeDuration> = []
        var seasons: Set<AnimeSeasonPreset> = []
        var years: Set<Int> = []
        var origins: Set<AnimeOrigin> = []
        var genreIds: Set<Int> = []
        var studioIds: Set<Int> = []
        var mylistStatuses: Set<MyListStatus> = []
        var order: AnimeOrder? = nil
        var licensedOnly: Bool = false
        var excludeCensored: Bool = false
        var minScore: Int? = nil
        var searchText: String = ""
    }

    private struct Snapshot: Codable {
        let kinds: [String]
        let statuses: [String]
        let ratings: [String]
        let durations: [String]
        let seasons: [String]
        /// Optional for backwards compatibility with older snapshots.
        let years: [Int]?
        let origins: [String]
        let genreIds: [Int]
        let studioIds: [Int]
        let mylistStatuses: [String]
        let order: String?
        let licensedOnly: Bool
        let excludeCensored: Bool
        let minScore: Int?
        let searchText: String
    }
}

/// Projection of an anime used by `AnimeFilterViewModel.applyClientSide` — lets the filter
/// match cached user-list items (or anything else) without depending on a concrete model.
struct FilterableAnime {
    let kind: String?
    let status: String?
    let rating: String?
    let durationMinutes: Int?
    let origin: String?
    let genreIds: [Int]
    let studioIds: [Int]
    let score: Double?
    let title: String?
    let titleRussian: String?
    let titleEnglish: String?
}
