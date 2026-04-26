//
//  ProfileView.swift
//  MyShikiPlayer
//
//  Profile screen: Hero + KPI + Status bar + Rating chart + Favourites.
//  Top-right gear button opens SettingsView (sheet).
//

import SwiftUI

struct ProfileView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var auth: ShikimoriAuthController
    @StateObject private var vm = ProfileViewModel()
    @State private var isSettingsPresented: Bool = false

    let onOpenAnime: (Int) -> Void
    let onSignOut: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                topBar
                if let profile = vm.profile {
                    ProfileHero(profile: profile)

                    kpiRow

                    if !vm.statusBuckets.isEmpty {
                        sectionBlock(kicker: "LISTS", title: "Списки") {
                            ProfileStatusBar(buckets: vm.statusBuckets)
                        }
                    }

                    if vm.ratingHistogram.reduce(0, +) > 0 {
                        sectionBlock(kicker: "SCORES", title: "Оценки") {
                            ProfileRatingChart(bins: vm.ratingHistogram, average: vm.averageScore)
                        }
                    }

                    if !vm.favourites.isEmpty {
                        sectionBlock(kicker: "FAVOURITES", title: "Избранное") {
                            ProfileFavouritesGrid(favourites: vm.favourites, onOpen: onOpenAnime)
                        }
                    }
                } else if vm.isLoading {
                    loadingView
                } else if let err = vm.errorMessage {
                    errorView(err)
                }

                Spacer(minLength: 48)
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .frame(maxWidth: 1120)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.bg)
        .task(id: auth.profile?.id) {
            guard let config = auth.configuration, let userId = auth.profile?.id else { return }
            await vm.reload(configuration: config, userId: userId)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(
                auth: auth,
                onSignOut: {
                    isSettingsPresented = false
                    onSignOut()
                },
                onClose: { isSettingsPresented = false }
            )
            .appTheme(theme)
        }
    }

    // MARK: - Top bar (kicker + settings button)

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PROFILE")
                    .font(.dsLabel(10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(theme.accent)
                Text("Мой аккаунт")
                    .font(.dsTitle(18, weight: .semibold))
                    .foregroundStyle(theme.fg)
            }
            Spacer()
            Button {
                isSettingsPresented = true
            } label: {
                HStack(spacing: 6) {
                    DSIcon(name: .gear, size: 14, weight: .semibold)
                    Text("Настройки")
                        .font(.dsBody(12, weight: .medium))
                }
                .foregroundStyle(theme.fg2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(theme.chipBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(theme.line, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Открыть настройки")
        }
    }

    // MARK: - KPI row

    private var kpiRow: some View {
        HStack(spacing: 14) {
            ProfileStatCard(
                value: "\(vm.totalTitles)",
                label: "Тайтлов"
            )
            ProfileStatCard(
                value: "\(totalWatchedEpisodes)",
                label: "Серий",
                caption: "Считаем по просмотренным статусам"
            )
            ProfileStatCard(
                value: vm.averageScore.map { String(format: "%.2f", $0) } ?? "—",
                label: "Средняя оценка"
            )
            ProfileStatCard(
                value: "\(vm.favourites.count)",
                label: "Избранное"
            )
        }
    }

    /// Compute an approximate number of watched episodes. Shikimori's stats has no
    /// ready-made counter — we use completed * 12 as a rough estimate. Not ideal, but
    /// this is our own surface and showing it beats hiding the number.
    private var totalWatchedEpisodes: Int {
        let completed = vm.statusBuckets.first { bucket in
            let key = bucket.groupedId?.split(separator: ",").first.map(String.init) ?? bucket.name?.lowercased()
            return key == "completed"
        }?.count ?? 0
        return completed * 12
    }

    // MARK: - Section block

    private func sectionBlock<Content: View>(
        kicker: String,
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker)
                    .font(.dsLabel(10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(theme.accent)
                Text(title)
                    .font(.dsTitle(20, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(theme.fg)
            }
            content()
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.line, lineWidth: 1)
                )
        }
    }

    // MARK: - States

    private var loadingView: some View {
        HStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .padding(.vertical, 80)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Text("Не удалось загрузить профиль")
                .font(.dsTitle(16, weight: .semibold))
                .foregroundStyle(theme.fg)
            Text(message)
                .font(.dsBody(12))
                .foregroundStyle(theme.fg3)
                .multilineTextAlignment(.center)
            Button("Повторить") {
                Task {
                    guard let config = auth.configuration, let uid = auth.profile?.id else { return }
                    await vm.reload(configuration: config, userId: uid, forceRefresh: true)
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}
