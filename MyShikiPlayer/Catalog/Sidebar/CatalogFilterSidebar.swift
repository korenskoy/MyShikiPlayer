//
//  CatalogFilterSidebar.swift
//  MyShikiPlayer
//
//  Catalog left column with filter sections. Paper theme, uppercase
//  mono section headers with a chevron — sections collapse on click
//  (logic lives in FilterSectionFrame). Uses the existing
//  AnimeFilterViewModel + FilterCatalog — data and persistence come from there.
//

import SwiftUI

struct CatalogFilterSidebar: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var filter: AnimeFilterViewModel
    @ObservedObject var catalog: FilterCatalog
    let onChange: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                genresSection
                yearSection
                earlierSection
                statusSection
                kindSection
                myListSection
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Sections

    private var genresSection: some View {
        FilterSectionFrame(title: "Жанры") {
            let items = catalog.genres.isEmpty
                ? FilterQuickGenres.fallback
                : catalog.genres.map { FilterQuickGenres.Item(id: $0.id ?? 0, name: $0.russian ?? $0.name ?? "—") }

            FlowLayout(spacing: 6) {
                ForEach(items, id: \.id) { g in
                    DSChip(
                        title: g.name,
                        isActive: filter.selectedGenreIds.contains(g.id),
                        size: .small,
                        action: {
                            toggle(genreId: g.id)
                        }
                    )
                }
            }
        }
    }

    private var yearSection: some View {
        FilterSectionFrame(title: "Год") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Self.yearOptions, id: \.self) { year in
                    CatalogFilterCheckboxRow(
                        label: "\(year)",
                        count: nil,
                        isChecked: filter.selectedYears.contains(year),
                        onToggle: { toggle(year: year) }
                    )
                }
            }
        }
    }

    private var earlierSection: some View {
        FilterSectionFrame(title: "Раньше") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Self.earlierPresets, id: \.self) { preset in
                    CatalogFilterCheckboxRow(
                        label: preset.displayName,
                        count: nil,
                        isChecked: filter.selectedSeasons.contains(preset),
                        onToggle: { toggle(season: preset) }
                    )
                }
            }
        }
    }

    /// Current year + 6 previous. Hard-coded fallback in case the system
    /// clock is shifted — we do not trust `Date()` blindly.
    private static var yearOptions: [Int] {
        let calendar = Calendar.current
        let current = calendar.component(.year, from: Date())
        let clamped = max(2000, min(current, 2100))
        return (0..<7).map { clamped - $0 }
    }

    /// AnimeSeasonPreset values for the "Earlier" section — ranges and decades.
    /// Year cases (year2025/year2026) are excluded here — they go into
    /// selectedYears as Int.
    private static let earlierPresets: [AnimeSeasonPreset] = [
        .range23to24,
        .range18to22,
        .range10to17,
        .range00to10,
        .decade1990s,
        .decade1980s,
        .ancient,
    ]

    private var statusSection: some View {
        FilterSectionFrame(title: "Статус") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(AnimeStatus.allCases, id: \.self) { s in
                    CatalogFilterCheckboxRow(
                        label: s.displayName,
                        count: nil,
                        isChecked: filter.selectedStatuses.contains(s),
                        onToggle: { toggle(status: s) }
                    )
                }
            }
        }
    }

    private var kindSection: some View {
        FilterSectionFrame(title: "Тип") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach([AnimeKind.tv, .movie, .ova, .ona, .special], id: \.self) { k in
                    CatalogFilterCheckboxRow(
                        label: k.displayName,
                        count: nil,
                        isChecked: filter.selectedKinds.contains(k),
                        onToggle: { toggle(kind: k) }
                    )
                }
            }
        }
    }

    private var myListSection: some View {
        FilterSectionFrame(title: "В моём списке") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(MyListStatus.allCases, id: \.self) { s in
                    CatalogFilterCheckboxRow(
                        label: s.displayName,
                        count: nil,
                        isChecked: filter.selectedMyListStatuses.contains(s),
                        onToggle: { toggle(myList: s) }
                    )
                }
            }
        }
    }

    // MARK: - Toggles

    private func toggle(genreId: Int) {
        if filter.selectedGenreIds.contains(genreId) {
            filter.selectedGenreIds.remove(genreId)
        } else {
            filter.selectedGenreIds.insert(genreId)
        }
        onChange()
    }

    private func toggle(season: AnimeSeasonPreset) {
        if filter.selectedSeasons.contains(season) {
            filter.selectedSeasons.remove(season)
        } else {
            filter.selectedSeasons.insert(season)
        }
        onChange()
    }

    private func toggle(year: Int) {
        if filter.selectedYears.contains(year) {
            filter.selectedYears.remove(year)
        } else {
            filter.selectedYears.insert(year)
        }
        onChange()
    }

    private func toggle(status: AnimeStatus) {
        if filter.selectedStatuses.contains(status) {
            filter.selectedStatuses.remove(status)
        } else {
            filter.selectedStatuses.insert(status)
        }
        onChange()
    }

    private func toggle(kind: AnimeKind) {
        if filter.selectedKinds.contains(kind) {
            filter.selectedKinds.remove(kind)
        } else {
            filter.selectedKinds.insert(kind)
        }
        onChange()
    }

    private func toggle(myList: MyListStatus) {
        if filter.selectedMyListStatuses.contains(myList) {
            filter.selectedMyListStatuses.remove(myList)
        } else {
            filter.selectedMyListStatuses.insert(myList)
        }
        onChange()
    }
}

// MARK: - Fallback quick genres when catalog hasn't loaded yet

private enum FilterQuickGenres {
    struct Item: Hashable { let id: Int; let name: String }
    static let fallback: [Item] = [] // empty until data arrives — server-driven
}

