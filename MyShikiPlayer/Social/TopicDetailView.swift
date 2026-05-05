//
//  TopicDetailView.swift
//  MyShikiPlayer
//
//  Full topic: hero (author + title) + body (plain) + linked anime card
//  + list of comments. Opens on top of SocialView.
//

import SwiftUI

struct TopicDetailView: View {
    @Environment(\.appTheme) var theme
    @StateObject var vm: TopicDetailViewModel

    let configuration: ShikimoriConfiguration
    let onClose: () -> Void
    let onOpenAnime: (Int) -> Void
    /// Reports the resolved topic title to the global navigation history
    /// (replaces a stub like "Обсуждение" once the data has loaded).
    let onTitleResolved: (Int, String) -> Void

    /// Card-driven entry: we already have the full Topic from the feed.
    init(
        configuration: ShikimoriConfiguration,
        topic: Topic,
        onClose: @escaping () -> Void,
        onOpenAnime: @escaping (Int) -> Void,
        onTitleResolved: @escaping (Int, String) -> Void = { _, _ in }
    ) {
        self.configuration = configuration
        self.onClose = onClose
        self.onOpenAnime = onOpenAnime
        self.onTitleResolved = onTitleResolved
        _vm = StateObject(wrappedValue: TopicDetailViewModel(topicId: topic.id, seed: topic))
    }

    /// History-restored entry: only the id (and last-known title) are known;
    /// the VM re-fetches the full Topic on appear.
    init(
        configuration: ShikimoriConfiguration,
        topicId: Int,
        title: String?,
        onClose: @escaping () -> Void,
        onOpenAnime: @escaping (Int) -> Void,
        onTitleResolved: @escaping (Int, String) -> Void = { _, _ in }
    ) {
        self.configuration = configuration
        self.onClose = onClose
        self.onOpenAnime = onOpenAnime
        self.onTitleResolved = onTitleResolved
        let stub: Topic? = title.map { Topic(
            id: topicId, topicTitle: $0, body: nil, htmlBody: nil,
            createdAt: nil, commentsCount: nil, forum: nil, user: nil,
            type: nil, linkedId: nil, linkedType: nil, linked: nil
        ) }
        _vm = StateObject(wrappedValue: TopicDetailViewModel(topicId: topicId, seed: stub))
    }

    @State private var highlightedCommentId: Int?
    /// Currently lightboxed image (tapped from topic body or any comment).
    /// `nil` keeps the lightbox dismissed. Single-image presentation — the
    /// lightbox renders one URL at a time, no cross-thread gallery navigation.
    @State private var lightboxImageURL: URL?

    /// Window width below which the sidebar collapses to keep the main column
    /// wide enough to host the 180pt meta column + body. Picked empirically
    /// against the design's 1500-wide canvas (1fr / 320 + 28 gap + 80 padding
    /// ≈ 1100 minimum).
    private static let sidebarBreakpoint: CGFloat = 1100

    var body: some View {
        ZStack {
            GeometryReader { geo in
                let showSidebar = geo.size.width >= Self.sidebarBreakpoint
                ScrollViewReader { proxy in
                    ScrollView {
                        HStack(alignment: .top, spacing: 28) {
                            mainColumn(proxy: proxy)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if showSidebar {
                                TopicSidebar(
                                    topic: vm.topic,
                                    stats: vm.linkedAnimeStats,
                                    isLoadingStats: vm.isLoadingLinkedAnimeStats,
                                    onOpenAnime: onOpenAnime
                                )
                                .frame(width: 320)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.top, 24)
                        .padding(.bottom, 48)
                        .frame(maxWidth: 1500)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .background(theme.bg)

            // Single-image lightbox overlay shared by topic body and all
            // comment rows. Tapping any inline image sets `lightboxImageURL`,
            // which translates into the array+index API the lightbox expects.
            ImageLightbox(
                urls: lightboxImageURL.map { [$0] } ?? [],
                selectedIndex: Binding(
                    get: { lightboxImageURL == nil ? nil : 0 },
                    set: { if $0 == nil { lightboxImageURL = nil } }
                )
            )
        }
        .task {
            await vm.load(configuration: configuration)
            if let topic = vm.topic, let title = topic.topicTitle, !title.isEmpty {
                onTitleResolved(topic.id, title)
            }
            await vm.loadLinkedAnimeStats(configuration: configuration)
        }
    }

    /// Main column — back-link, hero, topic body, then the flat-thread
    /// comments section. The linked-anime card is owned by the right sidebar
    /// (`RailPosterCTA`) so we don't duplicate it here. The auto-generated
    /// "Топик обсуждения [anime=N]…[/anime]." stub Shikimori uses for anime
    /// EntryTopics is also skipped — the title and poster already convey it.
    @ViewBuilder
    private func mainColumn(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            backLink
            if let topic = vm.topic {
                topicHero(topic)
                if !vm.topicSegments.isEmpty, !isStubEntryTopic(topic) {
                    FormattedBody(
                        segments: vm.topicSegments,
                        onOpenAnimeId: onOpenAnime,
                        onOpenImageURL: { lightboxImageURL = $0 },
                        commentResolvers: buildTopicResolvers()
                    )
                }
            }
            commentsSection(proxy: proxy)
            Spacer(minLength: 48)
        }
    }

    /// Anime EntryTopics on Shikimori always carry an auto-generated
    /// "Топик обсуждения …" body — there's no human-authored content to
    /// surface, so we skip the body block entirely. We rely on `linkedType`
    /// rather than scanning the body itself because the stub localises to
    /// other languages and BBCode quirks would otherwise leak through.
    private func isStubEntryTopic(_ topic: Topic) -> Bool {
        topic.linkedType == "Anime" && topic.linkedId != nil
    }

    /// Scrolls to the post with the given comment id and flashes it briefly so
    /// the user can pick it out after a parent-chip jump.
    private func jumpToComment(_ id: Int, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(id, anchor: .top)
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            highlightedCommentId = id
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                if highlightedCommentId == id {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        highlightedCommentId = nil
                    }
                }
            }
        }
    }
}

// MARK: - View helpers (extension keeps the main struct body within
// SwiftLint's type_body_length budget; private members on an extension of
// the same type stay accessible to the main body's view builders).

extension TopicDetailView {

    // MARK: - Back link (inline, scrolls with content)

    private var backLink: some View {
        Button(action: onClose) {
            HStack(spacing: 6) {
                DSIcon(name: .chevL, size: 12, weight: .semibold)
                Text("К ленте")
                    .font(.dsMono(11, weight: .medium))
                    .tracking(1)
            }
            .foregroundStyle(theme.fg3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Вернуться к ленте")
    }

    // MARK: - Hero

    private func topicHero(_ topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                TopicAvatar(user: topic.user, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.user?.nickname ?? "—")
                        .font(.dsBody(13, weight: .semibold))
                        .foregroundStyle(theme.fg)
                    Text(headerSubline(topic))
                        .font(.dsMono(11))
                        .foregroundStyle(theme.fg3)
                }
                Spacer()
            }
            Text(topic.topicTitle ?? "Без заголовка")
                .font(.dsTitle(26, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(theme.fg)
                .multilineTextAlignment(.leading)
            breadcrumb(topic)
        }
    }

    // MARK: - Comments

    private func commentsSection(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("КОММЕНТАРИИ")
                    .font(.dsLabel(10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(theme.accent)
                if let total = vm.topic?.commentsCount, total > 0 {
                    Text("\(total)")
                        .font(.dsMono(12, weight: .semibold))
                        .foregroundStyle(theme.fg)
                }
                Spacer()
                Text(commentsCounterText)
                    .font(.dsMono(12))
                    .foregroundStyle(theme.fg3)
                Button {
                    Task { await vm.reload(configuration: configuration) }
                } label: {
                    DSIcon(name: .refresh, size: 12, weight: .semibold)
                        .foregroundStyle(theme.fg2)
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(theme.chipBg)
                        )
                }
                .buttonStyle(.plain)
                .disabled(vm.isLoading)
                .help("Обновить топик и комментарии")
            }

            if vm.comments.isEmpty && vm.isLoading {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if vm.comments.isEmpty {
                Text("Комментариев пока нет.")
                    .font(.dsBody(12))
                    .foregroundStyle(theme.fg3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                let resolvers = buildCommentResolvers()
                let topicAuthorId = vm.topic?.user?.id
                // Order under the comments header: load-more on top (so the
                // older history is reached without crossing the pager
                // visually), then the decorative pageNav, then posts, then
                // a trailing pageNav copy for symmetry.
                loadMoreCommentsControl
                pageNav
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(vm.comments.enumerated()), id: \.element.id) { idx, comment in
                        LinearPostRow(
                            comment: comment,
                            isFirst: idx == 0,
                            segments: vm.commentSegments[comment.id],
                            isTopicAuthor: topicAuthorId != nil
                                && comment.user?.id == topicAuthorId,
                            parentRef: vm.parentRefs[comment.id],
                            isHighlighted: highlightedCommentId == comment.id,
                            onOpenAnimeId: onOpenAnime,
                            onOpenCommentId: { id in jumpToComment(id, proxy: proxy) },
                            onOpenImageURL: { lightboxImageURL = $0 },
                            commentResolvers: resolvers,
                            onJumpToParent: { id in jumpToComment(id, proxy: proxy) }
                        )
                        .id(comment.id)
                    }
                }
                .padding(.horizontal, 22)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.line, lineWidth: 1)
                )
                pageNav
            }
        }
    }

    /// Decorative pager — actual paging is driven by the "Загрузить ещё"
    /// control above the list. Hidden until we know `topic.commentsCount`,
    /// otherwise `currentPage` would jump from 1 to N as soon as the topic
    /// resolves.
    @ViewBuilder
    private var pageNav: some View {
        let totalPages = vm.totalPages
        if totalPages > 0 {
            let loadedPages = max(1, vm.loadedPagesCount)
            let current = max(1, totalPages - loadedPages + 1)
            LinearPageNav(
                currentPage: current,
                totalPages: totalPages,
                loaded: vm.comments.count,
                total: vm.topic?.commentsCount ?? vm.comments.count
            )
        }
    }

    /// Shown above the comments list (matches Shikimori's web layout where
    /// older history is reached by walking up). Mirrors the wording on the
    /// site: "Загрузить ещё N из M комментариев".
    @ViewBuilder
    private var loadMoreCommentsControl: some View {
        if vm.isLoadingMore {
            HStack {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            }
            .padding(.vertical, 12)
        } else if vm.canLoadMore {
            Button {
                Task { await vm.loadMore(configuration: configuration) }
            } label: {
                Text(loadMoreButtonText)
                    .font(.dsMono(11, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.chipBg)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var commentsCounterText: String {
        if let total = vm.topic?.commentsCount, total > vm.comments.count {
            return "\(vm.comments.count) из \(total)"
        }
        return "\(vm.comments.count)"
    }

    private var loadMoreButtonText: String {
        let total = vm.topic?.commentsCount ?? 0
        let remaining = max(0, total - vm.comments.count)
        let nextBatch = min(30, remaining)
        if total > 0, remaining > 0 {
            return "Загрузить ещё \(nextBatch) из \(total) комментариев"
        }
        return "Загрузить ещё"
    }

    // MARK: - Helpers

    private func headerSubline(_ topic: Topic) -> String {
        // Forum name moved into the breadcrumb under the title — keep only
        // the relative timestamp here so the author block stays compact.
        guard let created = topic.createdAt else { return "" }
        let fmt = RelativeDateTimeFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.unitsStyle = .short
        return fmt.localizedString(for: created, relativeTo: Date())
    }

}

