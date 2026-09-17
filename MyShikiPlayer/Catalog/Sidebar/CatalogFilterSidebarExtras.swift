//
//  CatalogFilterSidebarExtras.swift
//  MyShikiPlayer
//
//  Extra filter sections used by the Ongoings screen (score, duration,
//  age rating, source, studio, flags). Split out of CatalogFilterSidebar
//  to keep either file readable.
//

import SwiftUI

extension CatalogFilterSidebar {
    /// Minimum Shikimori score. Single choice — tapping the active chip clears it.
    var scoreSection: some View {
        FilterSectionFrame(title: "Рейтинг от") {
            HStack(spacing: 6) {
                ForEach(Self.scoreOptions, id: \.self) { value in
                    DSChip(
                        title: "\(value)+",
                        isActive: filter.minScore == value,
                        size: .small,
                        mono: true,
                        action: { select(minScore: value) }
                    )
                }
            }
        }
    }

    static let scoreOptions: [Int] = [6, 7, 8, 9]

    var durationSection: some View {
        FilterSectionFrame(title: "Длительность") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(AnimeDuration.allCases, id: \.self) { d in
                    CatalogFilterCheckboxRow(
                        label: d.displayName,
                        count: nil,
                        isChecked: filter.selectedDurations.contains(d),
                        onToggle: { toggle(duration: d) }
                    )
                }
            }
        }
    }

    var ratingSection: some View {
        FilterSectionFrame(title: "Возрастной рейтинг") {
            FlowLayout(spacing: 6) {
                ForEach(AnimeRating.allCases, id: \.self) { r in
                    DSChip(
                        title: r.displayName,
                        isActive: filter.selectedRatings.contains(r),
                        size: .small,
                        mono: true,
                        action: { toggle(rating: r) }
                    )
                }
            }
        }
    }

    var originSection: some View {
        FilterSectionFrame(title: "Первоисточник") {
            FlowLayout(spacing: 6) {
                ForEach(Self.originOptions, id: \.self) { o in
                    DSChip(
                        title: o.displayName,
                        isActive: filter.selectedOrigins.contains(o),
                        size: .small,
                        action: { toggle(origin: o) }
                    )
                }
            }
        }
    }

    /// Sources that actually show up in anime listings — `radio`, `card_game`
    /// and friends would only pad the column.
    static let originOptions: [AnimeOrigin] = [
        .original, .manga, .webManga, .lightNovel, .novel, .visualNovel, .game, .other,
    ]

    /// Studios are a few hundred entries — the list is search-driven, with the
    /// picked ones always pinned on top so they can be unpicked.
    var studiosSection: some View {
        FilterSectionFrame(title: "Студия") {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Поиск студии", text: $studioSearch)
                    .textFieldStyle(.roundedBorder)
                    .font(.dsBody(12))

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(visibleStudios) { studio in
                        CatalogFilterCheckboxRow(
                            label: studio.displayName,
                            count: nil,
                            isChecked: filter.selectedStudioIds.contains(studio.id),
                            onToggle: { toggle(studioId: studio.id) }
                        )
                    }
                }

                if visibleStudios.isEmpty {
                    Text(catalog.studios.isEmpty ? "Список загружается…" : "Ничего не найдено")
                        .font(.dsBody(11))
                        .foregroundStyle(theme.fg3)
                }
            }
        }
    }

    var visibleStudios: [Studio] {
        let selected = catalog.studios.filter { filter.selectedStudioIds.contains($0.id) }
        let query = studioSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return selected }
        let matches = catalog.studios
            .filter { !filter.selectedStudioIds.contains($0.id) }
            .filter { $0.displayName.localizedCaseInsensitiveContains(query) }
            .prefix(20)
        return selected + matches
    }

    var flagsSection: some View {
        FilterSectionFrame(title: "Прочее") {
            VStack(alignment: .leading, spacing: 4) {
                CatalogFilterCheckboxRow(
                    label: "Скрыть цензурируемое",
                    count: nil,
                    isChecked: filter.excludeCensored,
                    onToggle: {
                        filter.excludeCensored.toggle()
                        onChange()
                    }
                )
                CatalogFilterCheckboxRow(
                    label: "Только лицензированное",
                    count: nil,
                    isChecked: filter.licensedOnly,
                    onToggle: {
                        filter.licensedOnly.toggle()
                        onChange()
                    }
                )
            }
        }
    }

    func toggle(duration: AnimeDuration) {
        if filter.selectedDurations.contains(duration) {
            filter.selectedDurations.remove(duration)
        } else {
            filter.selectedDurations.insert(duration)
        }
        onChange()
    }

    func toggle(rating: AnimeRating) {
        if filter.selectedRatings.contains(rating) {
            filter.selectedRatings.remove(rating)
        } else {
            filter.selectedRatings.insert(rating)
        }
        onChange()
    }

    func toggle(origin: AnimeOrigin) {
        if filter.selectedOrigins.contains(origin) {
            filter.selectedOrigins.remove(origin)
        } else {
            filter.selectedOrigins.insert(origin)
        }
        onChange()
    }

    func toggle(studioId: Int) {
        if filter.selectedStudioIds.contains(studioId) {
            filter.selectedStudioIds.remove(studioId)
        } else {
            filter.selectedStudioIds.insert(studioId)
        }
        onChange()
    }

    func select(minScore: Int) {
        filter.minScore = filter.minScore == minScore ? nil : minScore
        onChange()
    }
}
