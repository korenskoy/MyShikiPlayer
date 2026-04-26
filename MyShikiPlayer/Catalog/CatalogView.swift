//
//  CatalogView.swift
//  MyShikiPlayer
//
//  Main catalog screen: left filter column + main grid.
//  Three card variants (grid/dense/rows) toggled by the header switch.
//  Data and filters reuse ExploreViewModel / AnimeFilterViewModel /
//  FilterCatalog — the UI is entirely new (paper theme).
//

import Combine
import SwiftUI

struct CatalogView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var auth: ShikimoriAuthController

    @StateObject private var model = ExploreViewModel()
    @StateObject private var filter = AnimeFilterViewModel(scope: "catalog")
    @StateObject private var filterCatalog = FilterCatalog()

    @AppStorage("catalog.variant") private var variantRaw: String = CatalogVariant.grid.rawValue
    @State private var reloadDebounce: AnyCancellable?
    @State private var openedDetailShikimoriId: Int?

    private var variant: Binding<CatalogVariant> {
        Binding(
            get: { CatalogVariant(rawValue: variantRaw) ?? .grid },
            set: { variantRaw = $0.rawValue }
        )
    }

    private var order: Binding<AnimeOrder?> {
        Binding(
            get: { filter.selectedOrder },
            set: {
                filter.selectedOrder = $0
                scheduleReload()
            }
        )
    }

    var body: some View {
        ZStack {
            gridLayout
            if let id = openedDetailShikimoriId, let config = auth.configuration {
                AnimeDetailsView(
                    auth: auth,
                    configuration: config,
                    shikimoriId: id,
                    onClose: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            openedDetailShikimoriId = nil
                        }
                    },
                    onOpenAnime: { item in
                        openedDetailShikimoriId = item.id
                    }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: openedDetailShikimoriId)
        .task(id: auth.profile?.id) {
            guard let config = auth.configuration else { return }
            filterCatalog.loadIfNeeded(configuration: config)
            model.reload(configuration: config, filter: filter)
        }
    }

    private var gridLayout: some View {
        HStack(alignment: .top, spacing: 28) {
            CatalogFilterSidebar(
                filter: filter,
                catalog: filterCatalog,
                onChange: scheduleReload
            )
            .frame(width: 240)

            VStack(alignment: .leading, spacing: 20) {
                CatalogHeader(
                    totalCount: model.items.count,
                    order: order,
                    variant: variant,
                    activeFacetLabels: activeFacetLabels,
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
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.items.isEmpty {
            centered(progressLabel: "Загружаем каталог…")
        } else if let error = model.errorMessage, model.items.isEmpty {
            errorState(error: error)
        } else if model.items.isEmpty {
            Text("Ничего не найдено")
                .font(.dsBody(14))
                .foregroundStyle(theme.fg3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            grid
        }
    }

    @ViewBuilder
    private var grid: some View {
        ScrollView(showsIndicators: true) {
            // VStack(spacing: 0) — without an explicit VStack, ScrollView lays out
            // elements with the default 8pt spacing, producing a double gap
            // between the grid and the pagination footer.
            VStack(alignment: .leading, spacing: 0) {
                switch variant.wrappedValue {
                case .grid:
                    LazyVGrid(columns: columns(count: 5), alignment: .leading, spacing: 14) {
                        ForEach(model.items, id: \.id) { item in
                            CatalogCard(item: item) { openDetails(item) }
                                .onAppear { prefetchIfNeeded(item) }
                        }
                    }
                case .dense:
                    LazyVGrid(columns: columns(count: 8), alignment: .leading, spacing: 10) {
                        ForEach(model.items, id: \.id) { item in
                            DensePosterCard(item: item) { openDetails(item) }
                                .onAppear { prefetchIfNeeded(item) }
                        }
                    }
                case .rows:
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(model.items, id: \.id) { item in
                            CatalogRow(item: item) { openDetails(item) }
                                .onAppear { prefetchIfNeeded(item) }
                        }
                    }
                }

                if model.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .padding(.top, 14)
                } else if model.reachedEnd, !model.items.isEmpty {
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

    private func columns(count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: count >= 8 ? 10 : 14, alignment: .top), count: count)
    }

    private func centered(progressLabel: String) -> some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(progressLabel).foregroundStyle(theme.fg3).font(.dsBody(13))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(error: String) -> some View {
        VStack(spacing: 10) {
            Text("Ошибка загрузки").font(.dsTitle(16)).foregroundStyle(theme.fg)
            Text(error)
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.fg2)
                .font(.dsBody(13))
                .frame(maxWidth: 480)
            DSButton("Повторить", variant: .secondary) {
                guard let config = auth.configuration else { return }
                model.reload(configuration: config, filter: filter)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pagination + reload

    private func prefetchIfNeeded(_ item: AnimeListItem) {
        guard item.id == model.items.last?.id else { return }
        guard let config = auth.configuration else { return }
        model.loadMoreIfNeeded(configuration: config, filter: filter)
    }

    private func scheduleReload() {
        reloadDebounce?.cancel()
        reloadDebounce = Just(())
            .delay(for: .milliseconds(350), scheduler: DispatchQueue.main)
            .sink { _ in
                guard let config = auth.configuration else { return }
                model.reload(configuration: config, filter: filter)
            }
    }

    private func resetAllFilters() {
        filter.selectedKinds.removeAll()
        filter.selectedStatuses.removeAll()
        filter.selectedRatings.removeAll()
        filter.selectedDurations.removeAll()
        filter.selectedSeasons.removeAll()
        filter.selectedOrigins.removeAll()
        filter.selectedGenreIds.removeAll()
        filter.selectedStudioIds.removeAll()
        filter.selectedMyListStatuses.removeAll()
        scheduleReload()
    }

    // MARK: - Navigation stub

    private func openDetails(_ item: AnimeListItem) {
        NetworkLogStore.shared.logUIEvent("catalog_open_details id=\(item.id) name=\(item.name)")
        withAnimation(.easeInOut(duration: 0.22)) {
            openedDetailShikimoriId = item.id
        }
    }

    // MARK: - Active filters summary

    private var activeFacetLabels: [String] {
        var labels: [String] = []
        labels.append(contentsOf: filter.selectedKinds.map(\.displayName))
        labels.append(contentsOf: filter.selectedStatuses.map(\.displayName))
        labels.append(contentsOf: filter.selectedSeasons.map(\.displayName))
        labels.append(contentsOf: filter.selectedMyListStatuses.map(\.displayName))
        labels.append(contentsOf: filter.selectedGenreIds.compactMap { id in
            filterCatalog.genres.first { $0.id == id }?.russian
        })
        return labels
    }
}
