//
//  HomeView.swift
//  MyShikiPlayer
//
//  Main feed: hero-billboard + "Continue watching" + "Trending" +
//  "New episodes" + "For you". Data — HomeViewModel (5 parallel
//  loaders). Card taps propagate up via onOpenDetails.
//

import SwiftUI

struct HomeView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var auth: ShikimoriAuthController
    @StateObject private var vm = HomeViewModel()

    let onOpenDetails: (Int) -> Void
    let onOpenSchedule: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let hero = vm.featuredHero {
                    HomeHeroBillboard(
                        item: hero,
                        onWatch: { onOpenDetails(hero.id) },
                        onOpenDetails: { onOpenDetails(hero.id) }
                    )
                    .padding(.bottom, 4)
                } else if vm.isLoading {
                    heroPlaceholder
                }

                if !vm.continueWatching.isEmpty {
                    sectionHeader(title: "Продолжить просмотр", action: nil)
                    LazyVGrid(columns: cols(4), alignment: .leading, spacing: 14) {
                        ForEach(vm.continueWatching) { item in
                            HomeContinueCard(item: item) { onOpenDetails(item.id) }
                        }
                    }
                }

                if !vm.trending.isEmpty {
                    sectionHeader(title: "В тренде сегодня", action: nil)
                    LazyVGrid(columns: cols(6), alignment: .leading, spacing: 14) {
                        ForEach(Array(vm.trending.enumerated()), id: \.element.id) { idx, item in
                            HomePosterCard(item: item, rank: idx + 1) { onOpenDetails(item.id) }
                        }
                    }
                }

                if !vm.newEpisodes.isEmpty {
                    sectionHeader(title: "Новые серии", action: ("Расписание →", onOpenSchedule))
                    LazyVGrid(columns: cols(6), alignment: .leading, spacing: 14) {
                        ForEach(vm.newEpisodes, id: \.id) { item in
                            HomePosterCard(item: item, rank: nil) { onOpenDetails(item.id) }
                        }
                    }
                }

                if vm.recommendations.count >= 1 {
                    sectionHeader(title: "Для вас", action: nil)
                    recommendationsGrid
                }

                if vm.isLoading && vm.trending.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                    .padding(.vertical, 40)
                }

                Spacer(minLength: 48)
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .frame(maxWidth: 1440)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.bg)
        .task(id: auth.profile?.id) {
            guard let config = auth.configuration else { return }
            await vm.reload(configuration: config, userId: auth.profile?.id)
        }
    }

    // MARK: - Helpers


    private func cols(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: count)
    }

    private func sectionHeader(title: String, action: (String, () -> Void)?) -> some View {
        HStack(alignment: .lastTextBaseline) {
            Text(title)
                .font(.dsTitle(22, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(theme.fg)
            Spacer()
            if let action {
                Button(action: action.1) {
                    Text(action.0)
                        .font(.dsBody(12, weight: .medium))
                        .foregroundStyle(theme.fg2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 32)
        .padding(.bottom, 14)
    }

    private var heroPlaceholder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(theme.bg2)
            .frame(height: 360)
            .overlay(ProgressView().controlSize(.small))
    }

    @ViewBuilder
    private var recommendationsGrid: some View {
        let items = vm.recommendations
        if items.isEmpty {
            EmptyView()
        } else {
            HStack(alignment: .top, spacing: 14) {
                if let feature = items.first {
                    HomeRecoFeature(item: feature) { onOpenDetails(feature.id) }
                        .frame(maxWidth: .infinity)
                }
                LazyVGrid(columns: cols(2), alignment: .leading, spacing: 14) {
                    ForEach(items.dropFirst().prefix(4), id: \.id) { item in
                        HomeRecoSmall(item: item) { onOpenDetails(item.id) }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
