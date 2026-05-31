//
//  LibraryView.swift
//  MyShikiPlayer
//
//  "Мои списки" screen. Left filter column (shared with Catalog), main area
//  with kicker + heading + the same sort chips Catalog has + variant toggle
//  + status tab bar + card grid (A/B/C).
//
//  Uses the existing AnimeListViewModel — its logic (paginated user_rates
//  loading, caching, GraphQL enrichment) is left intact. Sort state lives on
//  the shared AnimeFilterViewModel (`selectedOrder` + `selectedAscending`)
//  so it persists per scope alongside the rest of the filter set.
//

import SwiftUI

struct LibraryView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var auth: ShikimoriAuthController

    @StateObject private var model = AnimeListViewModel()
    @StateObject private var filter = AnimeFilterViewModel(scope: "library")
    @StateObject private var filterCatalog = FilterCatalog()

    @AppStorage("library.variant") private var variantRaw: String = CatalogVariant.grid.rawValue

    let onOpenDetails: (Int) -> Void

    /// Sort options Library supports. `.popularity` is intentionally absent —
    /// Shikimori GraphQL does not expose a per-item popularity field, so the
    /// chip would have no data to act on.
    private let sortOptions: [AnimeOrder] = [.ranked, .airedOn]

    private var variant: Binding<CatalogVariant> {
        Binding(
            get: { CatalogVariant(rawValue: variantRaw) ?? .grid },
            set: { variantRaw = $0.rawValue }
        )
    }

    private var order: Binding<AnimeOrder?> {
        Binding(
            get: { filter.selectedOrder },
            set: { filter.selectedOrder = $0 }
        )
    }

    private var ascending: Binding<Bool> {
        Binding(
            get: { filter.selectedAscending },
            set: { filter.selectedAscending = $0 }
        )
    }

    private var selectedTab: Binding<AnimeListViewModel.StatusTab> {
        Binding(
            get: { model.selectedTab },
            set: { newTab in
                model.selectedTab = newTab
                // Tab click is a coarse shortcut — clear the finer-grained
                // sidebar status selection so the grid reflects exactly what
                // the user just tapped instead of being silently overridden
                // by `model.selectedStatuses` (which has priority in
                // `visibleItems` and persists across launches).
                model.selectedStatuses = []
                if !filter.selectedMyListStatuses.isEmpty {
                    filter.selectedMyListStatuses = []
                }
            }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            CatalogFilterSidebar(
                filter: filter,
                catalog: filterCatalog,
                onChange: syncFilterToModel
            )
            .frame(width: 240)

            VStack(alignment: .leading, spacing: 20) {
                header
                LibraryStatusTabs(
                    selected: selectedTab,
                    counts: { model.count(for: $0) }
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
            guard let config = auth.configuration, let userId = auth.profile?.id else { return }
            filterCatalog.loadIfNeeded(configuration: config)
            await model.loadFilterEnumsIfNeeded(configuration: config)
            await model.reload(configuration: config, currentUserId: userId)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Моя библиотека")
                    .font(.dsDisplay(28, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(theme.fg)
                Text("· \(filteredItems.count)")
                    .font(.dsTitle(24))
                    .foregroundStyle(theme.fg3)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                if model.isLoading {
                    ProgressView().controlSize(.small)
                }
                CatalogSortChips(
                    order: order,
                    ascending: ascending,
                    options: sortOptions
                )

                Rectangle()
                    .fill(theme.line)
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 4)

                CatalogVariantToggle(selection: variant)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.visibleItems.isEmpty {
            centered(label: "Загружаем список…")
        } else if let error = model.errorMessage, model.visibleItems.isEmpty {
            errorState(message: error)
        } else if model.visibleItems.isEmpty {
            emptyState
        } else {
            grid
        }
    }

    /// Applies the sidebar filters that can be evaluated against fields we
    /// already have on `Item` (kind / production status / year / search). We
    /// intentionally do not filter by genre/studio/rating/origin here — the
    /// list endpoint did not return those fields, so the sidebar can't filter
    /// them client-side without extra requests. They stay in the UI for
    /// future wiring once enriched.
    private var filteredItems: [AnimeListViewModel.Item] {
        var items = model.visibleItems

        if !filter.selectedKinds.isEmpty {
            let allowed = Set(filter.selectedKinds.map(\.rawValue))
            items = items.filter { allowed.contains($0.kind.lowercased()) }
        }

        if !filter.selectedStatuses.isEmpty {
            let allowed = Set(filter.selectedStatuses.map(\.rawValue))
            items = items.filter { item in
                guard let raw = item.animeStatus?.lowercased() else { return false }
                return allowed.contains(raw)
            }
        }

        if !filter.selectedYears.isEmpty {
            items = items.filter { item in
                guard let year = Int(item.year) else { return false }
                return filter.selectedYears.contains(year)
            }
        }

        let query = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            items = items.filter { $0.title.lowercased().contains(query) }
        }

        return items
    }

    /// Applies the active sort order and direction on top of `filteredItems`.
    /// Items missing the chosen field (no global rating, non-numeric year)
    /// are pushed to the end regardless of direction — they're absent values,
    /// not "low" ones.
    private var sortedItems: [AnimeListViewModel.Item] {
        let items = filteredItems
        let asc = filter.selectedAscending

        func compare<T: Comparable>(_ l: T, _ r: T) -> Bool {
            asc ? l < r : l > r
        }

        switch filter.selectedOrder {
        case .ranked:
            return items.sorted { lhs, rhs in
                switch (lhs.animeScore, rhs.animeScore) {
                case let (l?, r?):
                    if l != r { return compare(l, r) }
                    return lhs.updatedAt > rhs.updatedAt
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.updatedAt > rhs.updatedAt
                }
            }
        case .airedOn:
            return items.sorted { lhs, rhs in
                let l = Int(lhs.year)
                let r = Int(rhs.year)
                switch (l, r) {
                case let (l?, r?):
                    if l != r { return compare(l, r) }
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none):
                    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
        default:
            // No explicit order picked — fall back to the natural "recently
            // updated" order that LibraryLoader produces.
            return items.sorted { compare($0.updatedAt, $1.updatedAt) }
        }
    }

    @ViewBuilder
    private var grid: some View {
        let items = sortedItems
        ScrollView(showsIndicators: true) {
            switch variant.wrappedValue {
            case .grid:
                LazyVGrid(columns: cols(5), alignment: .leading, spacing: 14) {
                    ForEach(items) { item in
                        CatalogCard(item: item.asAnimeListItem) { onOpenDetails(item.shikimoriId) }
                    }
                }
            case .dense:
                LazyVGrid(columns: cols(8), alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        DensePosterCard(item: item.asAnimeListItem) { onOpenDetails(item.shikimoriId) }
                    }
                }
            case .rows:
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(items) { item in
                        CatalogRow(item: item.asAnimeListItem) { onOpenDetails(item.shikimoriId) }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func cols(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: count >= 8 ? 10 : 14, alignment: .top), count: count)
    }

    private func centered(label: String) -> some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(label).font(.dsBody(13)).foregroundStyle(theme.fg3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 10) {
            Text("Ошибка загрузки")
                .font(.dsTitle(16))
                .foregroundStyle(theme.fg)
            Text(message)
                .font(.dsBody(13))
                .foregroundStyle(theme.fg2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            DSButton("Повторить", variant: .secondary) {
                guard let config = auth.configuration, let userId = auth.profile?.id else { return }
                Task { await model.reload(configuration: config, currentUserId: userId, forceRemote: true) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Пока пусто")
                .font(.dsTitle(16))
                .foregroundStyle(theme.fg)
            Text("Открой каталог и добавляй тайтлы в списки — они появятся здесь.")
                .font(.dsBody(13))
                .foregroundStyle(theme.fg2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filter sidebar sync

    private func syncFilterToModel() {
        model.selectedStatuses = Set(filter.selectedMyListStatuses.map(\.rawValue))
        if filter.selectedMyListStatuses.count == 1,
           let only = filter.selectedMyListStatuses.first,
           let tab = AnimeListViewModel.StatusTab(rawValue: only.rawValue) {
            model.selectedTab = tab
        } else if filter.selectedMyListStatuses.isEmpty {
            // Leave selectedTab alone — the user may have picked a tab manually.
        } else {
            model.selectedTab = .all
        }
    }
}
