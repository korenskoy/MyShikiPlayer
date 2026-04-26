//
//  ExploreView.swift
//  MyShikiPlayer
//

import SwiftUI
import Combine

/// Catalog browser backed by `GET /api/animes`. Shares filter UI with user-list screen
/// but applies every facet server-side and supports pagination.
struct ExploreView: View {
    @ObservedObject var auth: ShikimoriAuthController
    @StateObject private var model = ExploreViewModel()
    @StateObject private var filter = AnimeFilterViewModel(scope: "explore")
    @StateObject private var filterCatalog = FilterCatalog()
    @State private var reloadDebounce: AnyCancellable?

    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 152, maximum: 176), spacing: 12),
    ]

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 10) {
                searchBar
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            FilterSidebarView(
                model: filter,
                catalog: filterCatalog,
                mode: .catalog
            ) {
                scheduleReload()
            }
            .frame(width: 240)
        }
        .padding(12)
        .task(id: auth.profile?.id) {
            guard let config = auth.configuration else { return }
            filterCatalog.loadIfNeeded(configuration: config)
            model.reload(configuration: config, filter: filter)
        }
        .onChange(of: filter.searchText) { _ in
            scheduleReload()
        }
    }

    private var searchBar: some View {
        HUDPanel {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Поиск по каталогу...", text: $filter.searchText)
                    .textFieldStyle(.plain)

                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button("Обновить") {
                    guard let config = auth.configuration else { return }
                    model.reload(configuration: config, filter: filter)
                }
                .disabled(auth.configuration == nil)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.items.isEmpty {
            VStack(spacing: 10) {
                ProgressView()
                Text("Загружаем каталог...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = model.errorMessage, model.items.isEmpty {
            VStack(spacing: 10) {
                Text("Ошибка загрузки")
                    .font(.headline)
                Text(error)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Повторить") {
                    guard let config = auth.configuration else { return }
                    model.reload(configuration: config, filter: filter)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.items.isEmpty {
            Text("Ничего не найдено")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                    ForEach(model.items, id: \.id) { item in
                        ExploreCard(item: item)
                            .onAppear {
                                if item.id == model.items.last?.id {
                                    guard let config = auth.configuration else { return }
                                    model.loadMoreIfNeeded(configuration: config, filter: filter)
                                }
                            }
                    }
                }
                .padding(.bottom, 8)

                if model.isLoadingMore {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 12)
                } else if model.reachedEnd, !model.items.isEmpty {
                    Text("Конец списка")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                }
            }
        }
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
}

private struct ExploreCard: View {
    let item: AnimeListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.14))
                CachedRemoteImage(
                    url: posterURL,
                    contentMode: .fill,
                    placeholder: { ProgressView() },
                    failure: {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
                )
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(0.7079, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(displayTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .topLeading)

            Text(metaText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var displayTitle: String {
        if let russian = item.russian, !russian.isEmpty { return russian }
        return item.name
    }

    private var metaText: String {
        var parts: [String] = []
        if let kind = item.kind { parts.append(kind.uppercased()) }
        let year = (item.releasedOn ?? item.airedOn).flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
        if let year { parts.append(year) }
        if let score = item.score, !score.isEmpty, score != "0.0", score != "0" {
            parts.append("★\(score)")
        }
        return parts.joined(separator: "  ")
    }

    private var posterURL: URL? {
        let raw = item.image?.preview ?? item.image?.original ?? item.image?.x96
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        if raw.hasPrefix("/") {
            return ShikimoriURL.media(path: raw)
        }
        return URL(string: raw)
    }
}
