//
//  FilterFacetLabels.swift
//  MyShikiPlayer
//
//  Human-readable labels for the active facets, shown as chips under the
//  screen header. Shared by Catalog and Ongoings so the two can't drift.
//

import Foundation

extension AnimeFilterViewModel {
    /// Labels for every applied facet. Genre and studio names come from the
    /// reference catalog — ids alone would mean nothing to the reader, so an
    /// entry that isn't loaded yet is simply skipped.
    func activeFacetLabels(catalog: FilterCatalog) -> [String] {
        var labels: [String] = []
        if let minScore, minScore > 0 { labels.append("Рейтинг \(minScore)+") }
        labels.append(contentsOf: selectedKinds.map(\.displayName))
        labels.append(contentsOf: selectedStatuses.map(\.displayName))
        labels.append(contentsOf: selectedDurations.map(\.displayName))
        labels.append(contentsOf: selectedRatings.map(\.displayName))
        labels.append(contentsOf: selectedOrigins.map(\.displayName))
        labels.append(contentsOf: selectedYears.sorted(by: >).map(String.init))
        labels.append(contentsOf: selectedSeasons.map(\.displayName))
        labels.append(contentsOf: selectedMyListStatuses.map(\.displayName))
        labels.append(contentsOf: selectedGenreIds.compactMap { id in
            catalog.genres.first { $0.id == id }?.displayName
        })
        labels.append(contentsOf: selectedStudioIds.compactMap { id in
            catalog.studios.first { $0.id == id }?.displayName
        })
        if excludeMyList { labels.append("Нет в моём списке") }
        if excludeCensored { labels.append("Без цензурируемого") }
        if licensedOnly { labels.append("Лицензировано") }
        return labels
    }
}
