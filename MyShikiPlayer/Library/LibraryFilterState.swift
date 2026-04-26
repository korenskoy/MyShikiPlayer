//
//  LibraryFilterState.swift
//  MyShikiPlayer
//
//  Helpers around the Library filter state — `UserDefaults` keys + the
//  load-from-defaults bootstrap. Phase 4 split: state itself stays as
//  `@Published` properties on `AnimeListViewModel` (so SwiftUI bindings
//  do not break), but the persistence wiring lives here in one place.
//

import Foundation

enum LibraryFilterPersistence {
    enum Key {
        static let selectedTab = "animeList.selectedTab"
        static let searchText = "animeList.searchText"
        static let selectedKind = "animeList.selectedKind"
        static let selectedRating = "animeList.selectedRating"
        static let selectedSeason = "animeList.selectedSeason"
        static let selectedStatuses = "animeList.selectedStatuses"
    }

    /// Snapshot loaded from UserDefaults at VM init time. All values fall
    /// back to the same defaults the original code used inline.
    struct Snapshot {
        var selectedTab: AnimeListViewModel.StatusTab
        var searchText: String
        var selectedKind: String
        var selectedRating: String
        var selectedSeason: String
        var selectedStatuses: Set<String>
    }

    static func loadSnapshot() -> Snapshot {
        var snapshot = Snapshot(
            selectedTab: .all,
            searchText: UserDefaults.standard.string(forKey: Key.searchText) ?? "",
            selectedKind: UserDefaults.standard.string(forKey: Key.selectedKind) ?? "ALL",
            selectedRating: UserDefaults.standard.string(forKey: Key.selectedRating) ?? "ALL",
            selectedSeason: UserDefaults.standard.string(forKey: Key.selectedSeason) ?? "",
            selectedStatuses: []
        )
        if let rawTab = UserDefaults.standard.string(forKey: Key.selectedTab),
           let tab = AnimeListViewModel.StatusTab(rawValue: rawTab) {
            snapshot.selectedTab = tab
        }
        if let statuses = UserDefaults.standard.stringArray(forKey: Key.selectedStatuses) {
            snapshot.selectedStatuses = Set(statuses)
        }
        return snapshot
    }
}
