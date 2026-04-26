//
//  AnimeDetailsView.swift
//  MyShikiPlayer
//
//  Anime detail screen. Takes only shikimoriId — loads everything else by
//  itself. Top hero + two-column main section (1fr + 340px right column
//  with Score / Info table / Community stats).
//

import AppKit
import SwiftUI

struct AnimeDetailsView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var auth: ShikimoriAuthController
    @StateObject private var vm: AnimeDetailsViewModel
    @State private var playerWindowCoordinator = PlayerWindowCoordinator()
    @State private var linkCopiedFlash: Bool = false
    @State private var lightboxIndex: Int? = nil
    @State private var episodesCollapsed: Bool

    let onClose: () -> Void
    let onOpenAnime: (AnimeListItem) -> Void
    let onOpenAnimeId: ((Int) -> Void)?
    let onTitleResolved: ((Int, String) -> Void)?

    init(
        auth: ShikimoriAuthController,
        configuration: ShikimoriConfiguration,
        shikimoriId: Int,
        onClose: @escaping () -> Void,
        onOpenAnime: @escaping (AnimeListItem) -> Void,
        onOpenAnimeId: ((Int) -> Void)? = nil,
        onTitleResolved: ((Int, String) -> Void)? = nil
    ) {
        self.auth = auth
        self.onClose = onClose
        self.onOpenAnime = onOpenAnime
        self.onOpenAnimeId = onOpenAnimeId
        self.onTitleResolved = onTitleResolved
        _vm = StateObject(wrappedValue: AnimeDetailsViewModel(
            shikimoriId: shikimoriId,
            configuration: configuration,
            currentUserId: auth.profile?.id
        ))
        let storedCollapsed = UserDefaults.standard
            .object(forKey: Self.episodesCollapsedKey(shikimoriId: shikimoriId)) as? Bool ?? false
        _episodesCollapsed = State(initialValue: storedCollapsed)
    }

    private static func episodesCollapsedKey(shikimoriId: Int) -> String {
        "details.episodes.collapsed.\(shikimoriId)"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.bg.ignoresSafeArea()

            ScrollView(showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    DetailsHero(
                        vm: vm,
                        onWatch: openPlayer,
                        onToggleFavorite: { Task { await vm.toggleFavorite() } },
                        onOpenOnShikimori: openOnShikimori,
                        onCopyLink: copyLinkToClipboard,
                        statusButton: AnyView(statusButton),
                        studioButton: AnyView(studioButton),
                        linkCopiedFlash: $linkCopiedFlash
                    )

                    main
                        .padding(.horizontal, 40)
                        .padding(.bottom, 48)
                        .frame(maxWidth: 1440)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            ImageLightbox(urls: screenshotOriginalURLs, selectedIndex: $lightboxIndex)
        }
        .task { await vm.load() }
        .overlay {
            loadingOverlay
        }
        .onChange(of: vm.detail?.id) { _, _ in
            // As soon as detail arrives — notify history about the title.
            // Use the computed vm.title (with fallback to romaji/"—").
            guard vm.detail != nil else { return }
            let resolved = vm.title
            guard resolved != "—", !resolved.isEmpty else { return }
            onTitleResolved?(vm.shikimoriId, resolved)
        }
    }

    // MARK: - Status + Studio popovers (wired here, rendered inside hero)

    private var statusButton: some View {
        StatusPickerButton(
            currentStatus: vm.userStatus,
            isUpdating: vm.isUpdatingList,
            onSelect: { status in
                Task { await vm.setStatus(status) }
            }
        )
    }

    private var studioButton: some View {
        StudioPickerButton(
            entries: vm.catalogEntries,
            selectedId: vm.selectedTranslationId,
            onSelect: { id in
                vm.selectTranslation(id)
            }
        )
    }

    // MARK: - Main content

    @ViewBuilder
    private var main: some View {
        if vm.detail != nil {
            HStack(alignment: .top, spacing: 28) {
                leftColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                rightColumn
                    .frame(width: 340)
            }
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !vm.isAnons {
                DetailsSectionHeader(
                    kicker: "EPISODES",
                    title: "Эпизоды",
                    action: episodesAction,
                    isCollapsed: Binding(
                        get: { episodesCollapsed },
                        set: { newValue in
                            episodesCollapsed = newValue
                            UserDefaults.standard.set(
                                newValue,
                                forKey: Self.episodesCollapsedKey(shikimoriId: vm.shikimoriId)
                            )
                        }
                    )
                )
                if !episodesCollapsed {
                    EpisodeGrid(
                        episodeCount: vm.episodeCount,
                        watchedUpTo: vm.userEpisodesWatched,
                        episodesWithSources: vm.episodesWithSources,
                        episodePreviews: vm.episodePreviews,
                        episodeDurationMinutes: vm.detail?.duration,
                        onTap: openEpisode(_:)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            if let description = vm.detail?.description, !description.isEmpty {
                DetailsSectionHeader(kicker: "SYNOPSIS", title: "Описание", action: nil)
                DescriptionSection(rawDescription: description, onOpenAnimeId: onOpenAnimeId)
            }

            if !vm.allScreenshots.isEmpty {
                DetailsSectionHeader(
                    kicker: "SHOTS",
                    title: "Скриншоты",
                    action: vm.allScreenshots.count > 1 ? "\(vm.allScreenshots.count) шт." : nil
                )
                ScreenshotsSection(screenshots: vm.allScreenshots) { index in
                    lightboxIndex = index
                }
            }

            if !vm.trailerVideos.isEmpty {
                DetailsSectionHeader(
                    kicker: "VIDEOS",
                    title: "Трейлеры и ролики",
                    action: vm.trailerVideos.count > 1 ? "\(vm.trailerVideos.count) шт." : nil
                )
                TrailersSection(videos: vm.trailerVideos)
            }

            if !vm.related.isEmpty {
                DetailsSectionHeader(kicker: "SIMILAR", title: "Похожее", action: nil)
                SimilarSection(items: vm.related, onOpen: onOpenAnime)
            }
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Rating is impossible until the title is released — hide for announcements.
            if !vm.isAnons {
                StarRatingSurface(
                    userScore: vm.userScore,
                    isUpdating: vm.isUpdatingList,
                    onSetScore: { value in
                        Task { await vm.setScore(value) }
                    }
                )
            }

            if let detail = vm.detail {
                InfoTableSurface(detail: detail)
            }

            if let stats = vm.stats {
                CommunityStatsSurface(stats: stats)
            }
        }
        .padding(.top, 32)
    }

    // MARK: - States

    @ViewBuilder
    private var loadingOverlay: some View {
        switch vm.state {
        case .loading where vm.detail == nil:
            VStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Загружаем тайтл…")
                    .font(.dsBody(13))
                    .foregroundStyle(theme.fg3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
        case .error(let message) where vm.detail == nil:
            VStack(spacing: 12) {
                Text("Не удалось загрузить тайтл")
                    .font(.dsTitle(16))
                    .foregroundStyle(theme.fg)
                Text(message)
                    .font(.dsBody(13))
                    .foregroundStyle(theme.fg2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                DSButton("Повторить", variant: .secondary) { Task { await vm.load() } }
                DSButton("Назад", variant: .ghost, action: onClose)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
        default:
            EmptyView()
        }
    }

    // MARK: - Derived data

    private var episodesAction: String? {
        guard vm.episodeCount > 0 else { return nil }
        if vm.uniqueStudiosCount > 0 {
            return "Всего \(vm.episodeCount) · озвучка от \(vm.uniqueStudiosCount) \(studioWord(vm.uniqueStudiosCount))"
        }
        return "Всего \(vm.episodeCount)"
    }

    private func studioWord(_ count: Int) -> String {
        let rem100 = count % 100
        if rem100 >= 11 && rem100 <= 14 { return "студий" }
        switch count % 10 {
        case 1:       return "студии"
        default:      return "студий"
        }
    }

    private var screenshotOriginalURLs: [URL] {
        vm.allScreenshots.compactMap { shot in
            ScreenshotsSection.urlFor(raw: shot.original ?? shot.preview)
        }
    }

    // MARK: - Actions

    private func openEpisode(_ episode: Int) {
        guard !vm.isPreparingPlayback else { return }
        Task {
            await vm.preparePlayback(episode: episode)
            // Episode sync with Shikimori — 85% threshold inside PlaybackSession,
            // report arrives on episode transitions and on window close.
            vm.session.onEpisodeWatched = { [weak vm] watchedEpisode in
                guard let vm else { return }
                Task { await vm.markEpisodeWatched(watchedEpisode) }
            }
            playerWindowCoordinator.open(session: vm.session) {
                // After watching, markEpisodeWatched may already have posted the
                // event (85% threshold in the player) — but if the player closed
                // earlier, force a refresh here so a fresh userRate.episodes
                // arrives from the network.
                Task { await vm.load(forceRefresh: true) }
            }
        }
    }

    private func openPlayer() {
        openEpisode(vm.nextEpisodeToWatch)
    }

    private func openOnShikimori() {
        guard let url = shikimoriWebURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyLinkToClipboard() {
        guard let url = shikimoriWebURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        NetworkLogStore.shared.logUIEvent("details_link_copied id=\(vm.shikimoriId)")
        withAnimation(.easeInOut(duration: 0.15)) { linkCopiedFlash = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { linkCopiedFlash = false }
        }
    }

    private var shikimoriWebURL: URL? {
        auth.configuration?.webURLForAnime(shikimoriId: vm.shikimoriId)
    }
}
