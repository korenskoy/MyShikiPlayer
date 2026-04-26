//
//  AnimeListViewModel.swift
//  MyShikiPlayer
//

import SwiftUI
import Combine

@MainActor
final class AnimeListViewModel: ObservableObject {
    /// Persistence keys live in `LibraryFilterPersistence.Key` (Phase 4 split).
    /// Local typealias keeps the `didSet` lines short.
    private typealias PersistedKey = LibraryFilterPersistence.Key

    struct Item: Identifiable {
        let id: Int
        let shikimoriId: Int
        let title: String
        let kind: String
        let year: String
        let status: String
        let score: Int
        let episodesWatched: Int
        let posterURL: URL?
        let updatedAt: Date
        /// Anime production status (anons / ongoing / released / latest).
        let animeStatus: String?
        /// Raw Shikimori season string (e.g. "summer_2026", "2023_2024").
        let animeSeason: String?
    }

    private struct ListCacheEnvelope: Codable {
        let savedAt: Date
        let items: [Item]
    }

    private enum CacheConfig {
        // Bumped to v2 when animeStatus/animeSeason fields were added to Item.
        static let keyPrefix = "animeList.cache.v2."
        static let ttl: TimeInterval = 15 * 60
    }

    enum StatusTab: String, CaseIterable {
        case all
        case planned
        case watching
        case rewatching
        case completed
        case onHold = "on_hold"
        case dropped

        var title: String {
            switch self {
            case .all: return "Все"
            case .planned: return "Запланировано"
            case .watching: return "Смотрю"
            case .rewatching: return "Пересматриваю"
            case .completed: return "Просмотрено"
            case .onHold: return "Отложено"
            case .dropped: return "Брошено"
            }
        }

        var apiStatus: String? {
            self == .all ? nil : rawValue
        }
    }

    @Published private(set) var allItems: [Item] = []
    @Published var selectedTab: StatusTab = .all {
        didSet { UserDefaults.standard.set(selectedTab.rawValue, forKey: PersistedKey.selectedTab) }
    }
    @Published var searchText: String = "" {
        didSet { UserDefaults.standard.set(searchText, forKey: PersistedKey.searchText) }
    }
    @Published var selectedKind: String = "ALL" {
        didSet { UserDefaults.standard.set(selectedKind, forKey: PersistedKey.selectedKind) }
    }
    @Published var selectedRating: String = "ALL" {
        didSet { UserDefaults.standard.set(selectedRating, forKey: PersistedKey.selectedRating) }
    }
    @Published var selectedSeason: String = "" {
        didSet { UserDefaults.standard.set(selectedSeason, forKey: PersistedKey.selectedSeason) }
    }
    @Published var selectedStatuses: Set<String> = [] {
        didSet {
            UserDefaults.standard.set(Array(selectedStatuses).sorted(), forKey: PersistedKey.selectedStatuses)
        }
    }
    @Published private(set) var isLoading = false
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var kindOptions: [String] = ["ALL", "tv", "movie", "ova", "ona", "special", "music", "tv_13", "tv_24", "tv_48"]
    @Published private(set) var ratingOptions: [String] = ["ALL"]
    private var didLoadFilterEnums = false

    init() {
        let snapshot = LibraryFilterPersistence.loadSnapshot()
        selectedTab = snapshot.selectedTab
        searchText = snapshot.searchText
        selectedKind = snapshot.selectedKind
        selectedRating = snapshot.selectedRating
        selectedSeason = snapshot.selectedSeason
        selectedStatuses = snapshot.selectedStatuses
    }

    var visibleItems: [Item] {
        if !selectedStatuses.isEmpty {
            return allItems.filter { selectedStatuses.contains($0.status) }
        }
        if selectedTab == .all {
            return allItems
        }
        return allItems.filter { $0.status == selectedTab.rawValue }
    }

    var availableKinds: [String] {
        kindOptions
    }

    func loadFilterEnumsIfNeeded(configuration: ShikimoriConfiguration) async {
        guard !didLoadFilterEnums else { return }
        didLoadFilterEnums = true

        do {
            let graphql = ShikimoriGraphQLClient(configuration: configuration)
            async let kindsLoad = LibraryLoader.withRetry { try await graphql.enumValues(typeName: "AnimeKindString") }
            async let ratingsLoad = LibraryLoader.withRetry { try await graphql.enumValues(typeName: "AnimeRatingString") }
            let (kinds, ratings) = try await (kindsLoad, ratingsLoad)
            if !kinds.isEmpty {
                kindOptions = ["ALL"] + kinds.map { $0.lowercased() }
                if selectedKind != "ALL", !kindOptions.contains(selectedKind.lowercased()) {
                    selectedKind = "ALL"
                }
            }
            if !ratings.isEmpty {
                ratingOptions = ["ALL"] + ratings
                if selectedRating != "ALL", !ratingOptions.contains(selectedRating) {
                    selectedRating = "ALL"
                }
            }
        } catch {
            NetworkLogStore.shared.logAppError("filter_enum_load_failed \(error.localizedDescription)")
        }
    }

    func count(for tab: StatusTab) -> Int {
        if tab == .all { return allItems.count }
        return allItems.reduce(into: 0) { acc, item in
            if item.status == tab.rawValue { acc += 1 }
        }
    }

    func reload(configuration: ShikimoriConfiguration, currentUserId: Int, forceRemote: Bool = false) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if !forceRemote, let cached = loadCachedItems(userId: currentUserId) {
            allItems = cached
            NetworkLogStore.shared.logUIEvent("anime_list_cache_hit user_id=\(currentUserId) items=\(cached.count)")
            return
        }

        do {
            // Per-page / per-chunk retry happens inside LibraryLoader; wrapping
            // the whole thing in another withRetry would multiply attempts and
            // re-fetch already-loaded chunks.
            let loader = LibraryLoader(configuration: configuration)
            let result = try await loader.reload(
                userId: currentUserId,
                criteria: .init(
                    selectedKind: self.selectedKind,
                    selectedRating: self.selectedRating,
                    selectedSeason: self.selectedSeason,
                    searchText: self.searchText
                )
            )
            allItems = result.items
            saveCachedItems(allItems, userId: currentUserId)
            NetworkLogStore.shared.logUIEvent("anime_list_cache_store user_id=\(currentUserId) items=\(allItems.count)")

        } catch {
            errorMessage = error.localizedDescription
            NetworkLogStore.shared.logAppError("anime_list_reload_failed \(error.localizedDescription)")
        }
    }

    func incrementEpisode(for item: Item, configuration: ShikimoriConfiguration) async {
        await update(item: item, configuration: configuration, episodes: item.episodesWatched + 1, status: nil, score: nil)
    }

    func setStatus(for item: Item, status: StatusTab, configuration: ShikimoriConfiguration) async {
        guard status != .all else { return }
        await update(item: item, configuration: configuration, episodes: nil, status: status.rawValue, score: nil)
    }

    func setScore(for item: Item, score: Int, configuration: ShikimoriConfiguration) async {
        let clamped = min(10, max(0, score))
        await update(item: item, configuration: configuration, episodes: nil, status: nil, score: clamped)
    }

    func setEpisodesWatched(for item: Item, episodes: Int, configuration: ShikimoriConfiguration) async {
        let safeEpisodes = max(0, episodes)
        await update(item: item, configuration: configuration, episodes: safeEpisodes, status: nil, score: nil)
    }

    private func update(
        item: Item,
        configuration: ShikimoriConfiguration,
        episodes: Int?,
        status: String?,
        score: Int?
    ) async {
        isUpdating = true
        defer { isUpdating = false }

        let body = UserRateV2UpdateBody(
            userRate: .init(
                chapters: nil,
                episodes: episodes.map(String.init),
                volumes: nil,
                rewatches: nil,
                score: score.map(String.init),
                status: status,
                text: nil
            )
        )

        do {
            let loader = LibraryLoader(configuration: configuration)
            let updated = try await loader.updateRate(id: item.id, body: body)
            if let index = allItems.firstIndex(where: { $0.id == item.id }) {
                allItems[index] = Item(
                    id: updated.id,
                    shikimoriId: allItems[index].shikimoriId,
                    title: allItems[index].title,
                    kind: allItems[index].kind,
                    year: allItems[index].year,
                    status: updated.status,
                    score: updated.score,
                    episodesWatched: updated.episodes,
                    posterURL: allItems[index].posterURL,
                    updatedAt: updated.updatedAt,
                    animeStatus: allItems[index].animeStatus,
                    animeSeason: allItems[index].animeSeason
                )
            }
            invalidateListCache()
        } catch {
            errorMessage = error.localizedDescription
            NetworkLogStore.shared.logAppError("user_rate_update_failed \(error.localizedDescription)")
        }
    }
}

extension AnimeListViewModel.Item: Codable {}

private extension AnimeListViewModel {
    func cacheKey(userId: Int) -> String {
        let normalizedKind = selectedKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedRating = selectedRating.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedSeason = selectedSeason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let parts = [
            "u=\(userId)",
            "k=\(normalizedKind)",
            "r=\(normalizedRating)",
            "s=\(normalizedSeason)",
            "q=\(normalizedSearch)"
        ]
        return CacheConfig.keyPrefix + parts.joined(separator: "|")
    }

    func loadCachedItems(userId: Int) -> [Item]? {
        let key = cacheKey(userId: userId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        guard let envelope = try? JSONDecoder().decode(ListCacheEnvelope.self, from: data) else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        let age = Date().timeIntervalSince(envelope.savedAt)
        guard age <= CacheConfig.ttl else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        return envelope.items
    }

    func saveCachedItems(_ items: [Item], userId: Int) {
        let key = cacheKey(userId: userId)
        let envelope = ListCacheEnvelope(savedAt: Date(), items: items)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func invalidateListCache() {
        let keys = UserDefaults.standard.dictionaryRepresentation().keys
        for key in keys where key.hasPrefix(CacheConfig.keyPrefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
        NetworkLogStore.shared.logUIEvent("anime_list_cache_invalidate scope=all")
    }
}

