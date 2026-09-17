//
//  OngoingReleasesView.swift
//  MyShikiPlayer
//
//  Grid of currently airing titles, ordered by rating by default. Layout
//  and filters are the catalog ones (CatalogFilterSidebar + CatalogHeader +
//  ExploreViewModel) with a wider set of facet sections; `status=ongoing`
//  is pinned on the query instead of living in the filter, so "clear all"
//  can't turn this screen into the plain catalog.
//

import Combine
import SwiftUI

struct OngoingReleasesView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var auth: ShikimoriAuthController

    @StateObject private var model = ExploreViewModel(pinQueryFields: { $0.status = "ongoing" })
    @StateObject private var filter = AnimeFilterViewModel(scope: "ongoings")
    @StateObject private var filterCatalog = FilterCatalog()
    @ObservedObject private var myList = MyListIndex.shared
    @State private var reloadDebounce: AnyCancellable?

    let onOpenDetails: (Int) -> Void

    private static let sidebarSections: [CatalogFilterSidebar.Section] = [
        .score, .genres, .kindWithLength, .duration, .year, .earlier,
        .rating, .origin, .studios, .myList, .flags,
    ]

    private static let orderOptions: [AnimeOrder] = [.ranked, .popularity, .airedOn, .episodes]

    private var order: Binding<AnimeOrder?> {
        Binding(
            get: { filter.selectedOrder },
            set: {
                filter.selectedOrder = $0
                scheduleReload()
            }
        )
    }

    private var ascending: Binding<Bool> {
        Binding(
            get: { filter.selectedAscending },
            set: { filter.selectedAscending = $0 }
        )
    }

    /// "Not in my list" is applied here — Shikimori cannot express it in the
    /// query. Ascending is a client-side view too: the server always returns
    /// descending, same as in the catalog.
    private var displayedItems: [AnimeListItem] {
        var items = model.items
        if filter.excludeMyList, myList.isReady {
            items = items.filter { !myList.contains($0.id) }
        }
        return filter.selectedAscending ? items.reversed() : items
    }

    /// True while the list ids are still on the way — the grid waits instead
    /// of rendering titles that are about to disappear.
    private var isWaitingForMyList: Bool {
        filter.excludeMyList && !myList.isReady
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            CatalogFilterSidebar(
                filter: filter,
                catalog: filterCatalog,
                sections: Self.sidebarSections,
                onChange: scheduleReload
            )
            .frame(width: 240)

            VStack(alignment: .leading, spacing: 20) {
                CatalogHeader(
                    title: "Релизы",
                    totalCount: model.items.count,
                    order: order,
                    ascending: ascending,
                    orderOptions: Self.orderOptions,
                    activeFacetLabels: filter.activeFacetLabels(catalog: filterCatalog),
                    onResetFilters: resetAllFilters
                )

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bg)
        .task(id: auth.profile?.id) {
            guard let config = auth.configuration else { return }
            applyScreenDefaults()
            filterCatalog.loadIfNeeded(configuration: config)
            if let userId = auth.profile?.id {
                myList.loadIfNeeded(configuration: config, userId: userId)
            }
            guard model.items.isEmpty else { return }
            model.reload(configuration: config, filter: filter)
        }
        .onChange(of: filter.excludeMyList) { _, isOn in
            // The toggle may be flipped long after the screen appeared, and
            // the ids are only fetched on demand.
            guard isOn, let config = auth.configuration, let userId = auth.profile?.id else { return }
            myList.loadIfNeeded(configuration: config, userId: userId)
        }
        .onChange(of: displayedItems.count) { _, _ in
            // The client-side exclusion thins out pages: keep pulling until
            // the grid has something to show.
            guard displayedItems.count < 10 else { return }
            guard let config = auth.configuration else { return }
            model.loadMoreIfNeeded(configuration: config, filter: filter)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if (model.isLoading || isWaitingForMyList) && displayedItems.isEmpty {
            centered {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Загружаем онгоинги…")
                        .font(.dsBody(13))
                        .foregroundStyle(theme.fg3)
                }
            }
        } else if let error = model.errorMessage, displayedItems.isEmpty {
            centered {
                VStack(spacing: 10) {
                    Text("Ошибка загрузки")
                        .font(.dsTitle(16, weight: .semibold))
                        .foregroundStyle(theme.fg)
                    Text(error)
                        .font(.dsBody(13))
                        .foregroundStyle(theme.fg2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                    DSButton("Повторить", variant: .secondary) { reload() }
                }
            }
        } else if displayedItems.isEmpty {
            centered {
                Text("Ничего не найдено")
                    .font(.dsBody(14))
                    .foregroundStyle(theme.fg3)
            }
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView(showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(displayedItems, id: \.id) { item in
                        CatalogCard(item: item, showsEpisodesBadge: true) { openDetails(item) }
                            .onAppear { prefetchIfNeeded(item) }
                    }
                }

                if model.isLoadingMore {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                } else if model.reachedEnd {
                    Text("Конец списка")
                        .font(.dsLabel(10))
                        .tracking(1.2)
                        .foregroundStyle(theme.fg3)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 14)
                }
            }
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 5)
    }

    private func centered<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data

    /// Status is pinned on the query, so it must never sit in the facet set —
    /// otherwise it shows up as a removable chip that does nothing. Sort
    /// defaults to rating, but only until the user picks something else.
    private func applyScreenDefaults() {
        filter.selectedStatuses.removeAll()
        if filter.selectedOrder == nil { filter.selectedOrder = .ranked }
    }

    private func reload() {
        guard let config = auth.configuration else { return }
        model.reload(configuration: config, filter: filter)
    }

    private func scheduleReload() {
        reloadDebounce?.cancel()
        reloadDebounce = Just(())
            .delay(for: .milliseconds(350), scheduler: DispatchQueue.main)
            .sink { _ in reload() }
    }

    private func resetAllFilters() {
        filter.reset()
        applyScreenDefaults()
        scheduleReload()
    }

    private func prefetchIfNeeded(_ item: AnimeListItem) {
        guard item.id == displayedItems.last?.id else { return }
        guard let config = auth.configuration else { return }
        model.loadMoreIfNeeded(configuration: config, filter: filter)
    }

    private func openDetails(_ item: AnimeListItem) {
        NetworkLogStore.shared.logUIEvent("ongoings_open_details id=\(item.id) name=\(item.name)")
        onOpenDetails(item.id)
    }
}
