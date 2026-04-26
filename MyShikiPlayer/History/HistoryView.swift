//
//  HistoryView.swift
//  MyShikiPlayer
//
//  History screen. List of the latest viewing events, merged from the
//  player's local journal and Shikimori history. Groups by calendar day;
//  hover/focus reveals a delete icon for local entries. Remote entries
//  cannot be deleted — Shikimori does not allow it.
//

import SwiftUI

struct HistoryView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var auth: ShikimoriAuthController
    @StateObject private var vm = HistoryViewModel()

    let onOpenDetails: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let banner = vm.remoteErrorMessage {
                    remoteErrorBanner(banner)
                }

                if vm.items.isEmpty {
                    if vm.isLoading {
                        centered(label: "Загружаем историю…")
                    } else {
                        emptyState
                    }
                } else {
                    grouped
                }

                if !vm.items.isEmpty, vm.hasMore {
                    loadMoreFooter
                }

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .frame(maxWidth: 960)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.bg)
        .task(id: auth.profile?.id) {
            await vm.reload(configuration: auth.configuration, userId: auth.profile?.id)
            // Posters for local events — batch-enrich the ids that aren't
            // yet present in the PosterEnricher cache.
            if let config = auth.configuration {
                let ids = Array(Set(vm.items.map(\.shikimoriId)))
                await PosterEnricher.shared.enrich(configuration: config, ids: ids)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ИСТОРИЯ · HISTORY")
                    .font(.dsLabel(10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(theme.accent)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("История просмотра")
                        .font(.dsDisplay(28, weight: .bold))
                        .tracking(-0.5)
                        .foregroundStyle(theme.fg)
                    Text("· \(vm.items.count)")
                        .font(.dsTitle(24))
                        .foregroundStyle(theme.fg3)
                }
            }
            Spacer()
            if vm.isLoading || vm.isLoadingMore {
                ProgressView().controlSize(.small)
            }
            DSButton("Обновить", variant: .secondary) {
                Task {
                    await vm.reload(
                        configuration: auth.configuration,
                        userId: auth.profile?.id,
                        forceRefresh: true
                    )
                }
            }
        }
    }

    // MARK: - Grouped list

    private var grouped: some View {
        let groups = HistoryGrouping.byDay(vm.items)
        return LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(groups, id: \.title) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.title)
                        .font(.dsLabel(11, weight: .bold))
                        .tracking(1.4)
                        .foregroundStyle(theme.fg3)
                    VStack(spacing: 8) {
                        ForEach(group.items) { item in
                            HistoryRow(
                                item: item,
                                onOpen: { onOpenDetails(item.shikimoriId) },
                                onRemoveLocal: { vm.removeLocal(item: item) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var loadMoreFooter: some View {
        HStack {
            Spacer()
            DSButton(vm.isLoadingMore ? "Загрузка…" : "Загрузить ещё", variant: .secondary) {
                guard let config = auth.configuration, let userId = auth.profile?.id else { return }
                Task { await vm.loadMore(configuration: config, userId: userId) }
            }
            .disabled(vm.isLoadingMore)
            Spacer()
        }
    }

    // MARK: - States

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Пока пусто")
                .font(.dsTitle(16))
                .foregroundStyle(theme.fg)
            Text("Открывай эпизоды — здесь появится журнал просмотра.")
                .font(.dsBody(13))
                .foregroundStyle(theme.fg2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }

    private func centered(label: String) -> some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(label).font(.dsBody(13)).foregroundStyle(theme.fg3)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 40)
    }

    private func remoteErrorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            DSIcon(name: .bell, size: 14, weight: .medium)
                .foregroundStyle(theme.warn)
            VStack(alignment: .leading, spacing: 2) {
                Text("Не удалось обновить с Shikimori")
                    .font(.dsBody(12, weight: .semibold))
                    .foregroundStyle(theme.fg)
                Text(message)
                    .font(.dsMono(11))
                    .foregroundStyle(theme.fg3)
                    .lineLimit(2)
            }
            Spacer()
            Button("Повторить") {
                Task {
                    await vm.reload(
                        configuration: auth.configuration,
                        userId: auth.profile?.id,
                        forceRefresh: true
                    )
                }
            }
            .buttonStyle(.borderless)
            .font(.dsBody(12, weight: .medium))
            .foregroundStyle(theme.accent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.bg2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
    }
}
