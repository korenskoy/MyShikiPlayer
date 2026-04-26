//
//  FilterSidebarView.swift
//  MyShikiPlayer
//

import SwiftUI

/// Full sidebar with every filter section, mirroring shikimori.io's right rail.
struct FilterSidebarView: View {
    @ObservedObject var model: AnimeFilterViewModel
    @ObservedObject var catalog: FilterCatalog
    let mode: Mode
    let onApply: () -> Void

    @State private var expanded: Set<String> = [
        "status", "kind", "rating", "duration", "season", "origin", "mylist"
    ]

    @State private var genreQuery: String = ""
    @State private var studioQuery: String = ""

    enum Mode {
        /// Filter over user's personal list — server-side facets not supported for all sections.
        case userList
        /// Full catalog filter — every facet applies via `/api/animes`.
        case catalog
    }

    init(
        model: AnimeFilterViewModel,
        catalog: FilterCatalog,
        mode: Mode,
        onApply: @escaping () -> Void = {}
    ) {
        self.model = model
        self.catalog = catalog
        self.mode = mode
        self.onApply = onApply
    }

    private var showsMyList: Bool { mode == .userList }
    private var showsOrder: Bool { mode == .catalog }
    private var showsRating: Bool { mode == .catalog }
    private var showsDuration: Bool { mode == .catalog }
    private var showsOrigin: Bool { mode == .catalog }
    private var showsGenres: Bool { mode == .catalog }
    private var showsStudios: Bool { mode == .catalog }
    private var showsFlags: Bool { mode == .catalog }

    var body: some View {
        HUDPanel {
            VStack(alignment: .leading, spacing: 10) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if showsMyList {
                            mylistSection
                            Divider()
                        }
                        statusSection
                        kindSection
                        if showsOrder { orderSection }
                        seasonSection
                        if showsDuration { durationSection }
                        if showsRating { ratingSection }
                        if showsOrigin { originSection }
                        if showsGenres { genresSection }
                        if showsStudios && !catalog.studios.isEmpty { studiosSection }
                        if showsFlags { flagsSection }
                        scoreSection
                    }
                    .padding(.trailing, 4)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Фильтры")
                .font(.headline)
            if model.activeFacetCount > 0 {
                Text("\(model.activeFacetCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
            Spacer()
            Button {
                model.reset()
                onApply()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .disabled(model.isEmpty)
            .help("Сбросить все фильтры")
        }
    }

    private var mylistSection: some View {
        FilterSection(
            title: "Список",
            activeCount: model.selectedMyListStatuses.count,
            isExpanded: binding("mylist")
        ) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(MyListStatus.allCases, id: \.self) { status in
                    FilterCheckboxRow(
                        title: status.displayName,
                        isOn: model.selectedMyListStatuses.contains(status)
                    ) {
                        model.toggle(status, in: &model.selectedMyListStatuses)
                        onApply()
                    }
                }
            }
        }
    }

    private var statusSection: some View {
        FilterSection(
            title: "Статус",
            activeCount: model.selectedStatuses.count,
            isExpanded: binding("status")
        ) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AnimeStatus.allCases, id: \.self) { status in
                    FilterCheckboxRow(
                        title: status.displayName,
                        isOn: model.selectedStatuses.contains(status)
                    ) {
                        model.toggle(status, in: &model.selectedStatuses)
                        onApply()
                    }
                }
            }
        }
    }

    private var kindSection: some View {
        FilterSection(
            title: "Тип",
            activeCount: model.selectedKinds.count,
            isExpanded: binding("kind")
        ) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AnimeKind.allCases, id: \.self) { kind in
                    FilterCheckboxRow(
                        title: kind.displayName,
                        isOn: model.selectedKinds.contains(kind)
                    ) {
                        model.toggle(kind, in: &model.selectedKinds)
                        onApply()
                    }
                }
            }
        }
    }

    private var orderSection: some View {
        FilterSection(
            title: "Сортировка",
            activeCount: model.selectedOrder == nil ? 0 : 1,
            isExpanded: binding("order")
        ) {
            VStack(alignment: .leading, spacing: 2) {
                FilterCheckboxRow(
                    title: "По умолчанию",
                    isOn: model.selectedOrder == nil
                ) {
                    model.selectedOrder = nil
                    onApply()
                }
                ForEach(AnimeOrder.allCases, id: \.self) { order in
                    FilterCheckboxRow(
                        title: order.displayName,
                        isOn: model.selectedOrder == order
                    ) {
                        model.selectedOrder = model.selectedOrder == order ? nil : order
                        onApply()
                    }
                }
            }
        }
    }

    private var seasonSection: some View {
        FilterSection(
            title: "Сезон",
            activeCount: model.selectedSeasons.count,
            isExpanded: binding("season")
        ) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AnimeSeasonPreset.allCases, id: \.self) { season in
                    FilterCheckboxRow(
                        title: season.displayName,
                        isOn: model.selectedSeasons.contains(season)
                    ) {
                        model.toggle(season, in: &model.selectedSeasons)
                        onApply()
                    }
                }
            }
        }
    }

    private var durationSection: some View {
        FilterSection(
            title: "Длительность",
            activeCount: model.selectedDurations.count,
            isExpanded: binding("duration")
        ) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AnimeDuration.allCases, id: \.self) { duration in
                    FilterCheckboxRow(
                        title: duration.displayName,
                        isOn: model.selectedDurations.contains(duration)
                    ) {
                        model.toggle(duration, in: &model.selectedDurations)
                        onApply()
                    }
                }
            }
        }
    }

    private var ratingSection: some View {
        FilterSection(
            title: "Рейтинг",
            activeCount: model.selectedRatings.count,
            isExpanded: binding("rating")
        ) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AnimeRating.allCases, id: \.self) { rating in
                    FilterCheckboxRow(
                        title: rating.displayName,
                        isOn: model.selectedRatings.contains(rating)
                    ) {
                        model.toggle(rating, in: &model.selectedRatings)
                        onApply()
                    }
                }
            }
        }
    }

    private var originSection: some View {
        FilterSection(
            title: "Первоисточник",
            activeCount: model.selectedOrigins.count,
            isExpanded: binding("origin")
        ) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AnimeOrigin.allCases, id: \.self) { origin in
                    FilterCheckboxRow(
                        title: origin.displayName,
                        isOn: model.selectedOrigins.contains(origin)
                    ) {
                        model.toggle(origin, in: &model.selectedOrigins)
                        onApply()
                    }
                }
            }
        }
    }

    private var genresSection: some View {
        GenresFilterSection(
            model: model,
            catalog: catalog,
            isExpanded: binding("genres"),
            query: $genreQuery,
            onApply: onApply
        )
    }

    private var studiosSection: some View {
        StudiosFilterSection(
            model: model,
            catalog: catalog,
            isExpanded: binding("studios"),
            query: $studioQuery,
            onApply: onApply
        )
    }

    private var flagsSection: some View {
        FilterSection(
            title: "Прочее",
            activeCount: (model.licensedOnly ? 1 : 0) + (model.excludeCensored ? 1 : 0),
            isExpanded: binding("flags")
        ) {
            VStack(alignment: .leading, spacing: 2) {
                FilterCheckboxRow(
                    title: "Только лицензированные",
                    isOn: model.licensedOnly
                ) {
                    model.licensedOnly.toggle()
                    onApply()
                }
                FilterCheckboxRow(
                    title: "Скрыть цензурное",
                    isOn: model.excludeCensored
                ) {
                    model.excludeCensored.toggle()
                    onApply()
                }
            }
        }
    }

    private var scoreSection: some View {
        FilterSection(
            title: "Мин. оценка",
            activeCount: (model.minScore ?? 0) > 0 ? 1 : 0,
            isExpanded: binding("score")
        ) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(model.minScore ?? 0)")
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 22, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { Double(model.minScore ?? 0) },
                            set: { model.minScore = Int($0); onApply() }
                        ),
                        in: 0...10,
                        step: 1
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func binding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(key) },
            set: { newValue in
                if newValue { expanded.insert(key) } else { expanded.remove(key) }
            }
        )
    }

}

private struct GenresFilterSection: View {
    @ObservedObject var model: AnimeFilterViewModel
    @ObservedObject var catalog: FilterCatalog
    @Binding var isExpanded: Bool
    @Binding var query: String
    let onApply: () -> Void

    var body: some View {
        FilterSection(
            title: "Жанры",
            activeCount: model.selectedGenreIds.count,
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 4) {
                if catalog.genres.isEmpty {
                    Text(catalog.isLoading ? "Загрузка..." : "Недостаточно данных")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    TextField("Поиск жанра", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    let filtered = filteredGenres
                    ForEach(filtered) { genre in
                        FilterCheckboxRow(
                            title: genre.displayName,
                            isOn: model.selectedGenreIds.contains(genre.id)
                        ) {
                            model.toggle(genre.id, in: &model.selectedGenreIds)
                            onApply()
                        }
                    }
                    if filtered.isEmpty {
                        Text("Ничего не найдено")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var filteredGenres: [Genre] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return catalog.genres }
        return catalog.genres.filter { g in
            g.displayName.lowercased().contains(q) || g.name.lowercased().contains(q)
        }
    }
}

private struct StudiosFilterSection: View {
    @ObservedObject var model: AnimeFilterViewModel
    @ObservedObject var catalog: FilterCatalog
    @Binding var isExpanded: Bool
    @Binding var query: String
    let onApply: () -> Void

    var body: some View {
        FilterSection(
            title: "Студии",
            activeCount: model.selectedStudioIds.count,
            isExpanded: $isExpanded
        ) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Поиск студии", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                let filtered = filteredStudios
                ForEach(filtered) { studio in
                    FilterCheckboxRow(
                        title: studio.displayName,
                        isOn: model.selectedStudioIds.contains(studio.id)
                    ) {
                        model.toggle(studio.id, in: &model.selectedStudioIds)
                        onApply()
                    }
                }
                if filtered.isEmpty {
                    Text(query.isEmpty ? "Начните вводить название" : "Ничего не найдено")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var filteredStudios: [Studio] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return Array(catalog.studios.prefix(30)) }
        return catalog.studios.filter { s in
            s.displayName.lowercased().contains(q) || s.name.lowercased().contains(q)
        }
    }
}
