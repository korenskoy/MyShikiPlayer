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
    /// Sections the host screen wants to show, in render order. The catalog
    /// keeps the original short set; Ongoings asks for the full one minus
    /// the status facet, which is fixed for that screen.
    enum Section: Hashable {
        case score
        case genres
        case year
        case earlier
        case status
        /// Short kind list: TV / Movie / OVA / ONA / Special.
        case kind
        /// Full kind list including the TV length buckets (tv_13/tv_24/tv_48),
        /// which is how Shikimori separates short seasons from endless shows.
        case kindWithLength
        case duration
        case rating
        case origin
        case studios
        case myList
        /// Censored / licensed toggles.
        case flags

        static let catalogDefault: [Section] = [.genres, .year, .earlier, .status, .kind, .myList]
    }

    @Environment(\.appTheme) var theme
    @ObservedObject var filter: AnimeFilterViewModel
    @ObservedObject var catalog: FilterCatalog
    var sections: [Section] = Section.catalogDefault
    let onChange: () -> Void

    @State var studioSearch: String = ""

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(sections, id: \.self) { section in
                    self.section(section)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func section(_ section: Section) -> some View {
        switch section {
        case .score:          scoreSection
        case .genres:         genresSection
        case .year:           yearSection
        case .earlier:        earlierSection
        case .status:         statusSection
        case .kind:           kindSection(kinds: Self.shortKinds)
        case .kindWithLength: kindSection(kinds: Self.kindsWithLength)
        case .duration:       durationSection
        case .rating:         ratingSection
        case .origin:         originSection
        case .studios:        studiosSection
        case .myList:         myListSection
        case .flags:          flagsSection
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

    private static let shortKinds: [AnimeKind] = [.tv, .movie, .ova, .ona, .special]
    /// `tv_13`/`tv_24`/`tv_48` are Shikimori's own length buckets — the only
    /// server-side way to tell a one-cour show from a decade-long one.
    private static let kindsWithLength: [AnimeKind] = [
        .tv, .tv13, .tv24, .tv48, .ona, .ova, .movie, .special, .tvSpecial, .music,
    ]

    private func kindSection(kinds: [AnimeKind]) -> some View {
        FilterSectionFrame(title: "Тип") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(kinds, id: \.self) { k in
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
                CatalogFilterCheckboxRow(
                    label: "Нет в моём списке",
                    count: nil,
                    isChecked: filter.excludeMyList,
                    onToggle: toggleExcludeMyList
                )
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
            // Picking a status contradicts "not in my list" — drop it.
            filter.excludeMyList = false
        }
        onChange()
    }

    private func toggleExcludeMyList() {
        filter.excludeMyList.toggle()
        if filter.excludeMyList { filter.selectedMyListStatuses.removeAll() }
        onChange()
    }
}

// MARK: - Fallback quick genres when catalog hasn't loaded yet

private enum FilterQuickGenres {
    struct Item: Hashable { let id: Int; let name: String }
    static let fallback: [Item] = [] // empty until data arrives — server-driven
}
