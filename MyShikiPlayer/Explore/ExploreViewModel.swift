//
//  ExploreViewModel.swift
//  MyShikiPlayer
//

import Foundation
import Combine

/// Drives the catalog Explore screen: fetches `/api/animes` with filter-derived query,
/// exposes results, pagination and error state.
@MainActor
final class ExploreViewModel: ObservableObject {
    private enum Constants {
        static let pageSize = 50
        static let maxPages = 20
    }

    @Published private(set) var items: [AnimeListItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var reachedEnd = false

    private var currentPage = 1
    private var activeTask: Task<Void, Never>?
    private let pinQueryFields: (inout AnimeListQuery) -> Void

    /// `pinQueryFields` runs after the filter has built the query — that is
    /// where a screen forces the facets it owns. The default drops `mylist`:
    /// the plain catalog is not a user-list screen.
    init(pinQueryFields: @escaping (inout AnimeListQuery) -> Void = { $0.mylist = nil }) {
        self.pinQueryFields = pinQueryFields
    }

    func reload(configuration: ShikimoriConfiguration, filter: AnimeFilterViewModel) {
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.performReload(configuration: configuration, filter: filter)
        }
    }

    func loadMoreIfNeeded(configuration: ShikimoriConfiguration, filter: AnimeFilterViewModel) {
        guard !reachedEnd, !isLoading, !isLoadingMore else { return }
        Task { [weak self] in
            await self?.performLoadMore(configuration: configuration, filter: filter)
        }
    }

    private func performReload(configuration: ShikimoriConfiguration, filter: AnimeFilterViewModel) async {
        isLoading = true
        errorMessage = nil
        reachedEnd = false
        currentPage = 1
        defer { isLoading = false }

        let rest = ShikimoriRESTClient(configuration: configuration)
        var query = filter.buildQuery(limit: Constants.pageSize, page: 1)
        pinQueryFields(&query)

        do {
            let chunk = try await rest.animes(query: query)
            if Task.isCancelled { return }
            items = chunk
            if chunk.count < Constants.pageSize { reachedEnd = true }
            NetworkLogStore.shared.logUIEvent("explore_reload page=1 items=\(chunk.count) facets=\(filter.activeFacetCount)")
            // Enrich posters of missing_preview titles via GraphQL.
            let enriched = await PosterEnricher.shared.enriched(configuration: configuration, items: items)
            if !Task.isCancelled { items = enriched }
        } catch {
            if Task.isCancelled { return }
            errorMessage = error.localizedDescription
            NetworkLogStore.shared.logAppError("explore_reload_failed \(error.localizedDescription)")
        }
    }

    private func performLoadMore(configuration: ShikimoriConfiguration, filter: AnimeFilterViewModel) async {
        guard !reachedEnd, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        currentPage += 1
        guard currentPage <= Constants.maxPages else {
            reachedEnd = true
            return
        }

        let rest = ShikimoriRESTClient(configuration: configuration)
        var query = filter.buildQuery(limit: Constants.pageSize, page: currentPage)
        pinQueryFields(&query)

        do {
            let chunk = try await rest.animes(query: query)
            if Task.isCancelled { return }
            let enrichedChunk = await PosterEnricher.shared.enriched(configuration: configuration, items: chunk)
            if Task.isCancelled { return }
            // Dedupe by id — Shikimori with order=ranked/popularity sometimes
            // returns the same titles across page boundaries. ForEach(id:) with
            // duplicates breaks LazyVGrid: SwiftUI merges them into a single
            // cell, leaving the rest as gaps between rows.
            let existing = Set(items.map(\.id))
            let fresh = enrichedChunk.filter { !existing.contains($0.id) }
            items.append(contentsOf: fresh)
            let dupes = chunk.count - fresh.count
            if chunk.count < Constants.pageSize { reachedEnd = true }
            NetworkLogStore.shared.logUIEvent(
                "explore_load_more page=\(currentPage) received=\(chunk.count) new=\(fresh.count) dupes=\(dupes)"
            )
        } catch {
            if Task.isCancelled { return }
            errorMessage = error.localizedDescription
            NetworkLogStore.shared.logAppError("explore_load_more_failed \(error.localizedDescription)")
        }
    }
}
