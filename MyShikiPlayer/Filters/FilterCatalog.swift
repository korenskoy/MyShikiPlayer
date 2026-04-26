//
//  FilterCatalog.swift
//  MyShikiPlayer
//

import Foundation
import Combine

/// Session-wide cache of Shikimori reference catalogs used by the filter UI.
@MainActor
final class FilterCatalog: ObservableObject {
    @Published private(set) var genres: [Genre] = []
    @Published private(set) var studios: [Studio] = []
    @Published private(set) var isLoading = false

    private var didLoad = false
    private var loadTask: Task<Void, Never>?

    func loadIfNeeded(configuration: ShikimoriConfiguration) {
        guard !didLoad, loadTask == nil else { return }
        loadTask = Task { [weak self] in
            await self?.performLoad(configuration: configuration)
        }
    }

    private func performLoad(configuration: ShikimoriConfiguration) async {
        isLoading = true
        defer {
            isLoading = false
            loadTask = nil
        }

        let rest = ShikimoriRESTClient(configuration: configuration)
        async let genresLoad: [Genre] = (try? rest.genres()) ?? []
        async let studiosLoad: [Studio] = (try? rest.studios()) ?? []
        let (loadedGenres, loadedStudios) = await (genresLoad, studiosLoad)

        let animeGenres = loadedGenres.filter { genre in
            guard let type = genre.entryType?.lowercased() else { return true }
            return type == "anime"
        }

        genres = animeGenres.isEmpty ? loadedGenres : animeGenres
        studios = loadedStudios
        didLoad = true

        NetworkLogStore.shared.logUIEvent(
            "filter_catalog_loaded genres=\(genres.count) studios=\(studios.count)"
        )
    }
}
