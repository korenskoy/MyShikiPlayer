//
//  SocialView.swift
//  MyShikiPlayer
//
//  Social screen: three tabs — Friends, Discussions, Reviews.
//  Discussions and reviews share the same mechanism (forum topics);
//  friends is a separate stream (friends + histories).
//

import SwiftUI

struct SocialView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var auth: ShikimoriAuthController
    @StateObject private var vm = SocialViewModel()
    @State private var selectedTopic: Topic?

    let onOpenAnime: (Int) -> Void

    var body: some View {
        Group {
            if let topic = selectedTopic, let config = auth.configuration {
                TopicDetailView(
                    configuration: config,
                    topic: topic,
                    onClose: closeDetail,
                    onOpenAnime: { id in
                        selectedTopic = nil
                        onOpenAnime(id)
                    }
                )
                .id(topic.id)
            } else {
                feedView
            }
        }
        .background(theme.bg)
        .task(id: auth.profile?.id) {
            await loadActiveTab()
        }
        .onChange(of: vm.selectedTab) { _, _ in
            Task { await loadActiveTab() }
        }
        .overlay {
            if selectedTopic != nil {
                Button { closeDetail() } label: { EmptyView() }
                    .keyboardShortcut(.escape, modifiers: [])
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }

    private var feedView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                SocialTabBar(selected: $vm.selectedTab)
                    .padding(.top, 18)
                    .padding(.bottom, 16)
                tabContent
                Spacer(minLength: 48)
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func closeDetail() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTopic = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COMMUNITY")
                .font(.dsLabel(10, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(theme.accent)
            HStack {
                Text("Лента")
                    .font(.dsTitle(28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(theme.fg)
                Spacer()
                Button(action: refreshActiveTab) {
                    HStack(spacing: 6) {
                        DSIcon(name: .refresh, size: 13, weight: .semibold)
                        Text("Обновить")
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
            }
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch vm.selectedTab {
        case .friends:     friendsContent
        case .discussions: forumContent(state: vm.discussions, tab: .discussions)
        case .reviews:     forumContent(state: vm.reviews, tab: .reviews)
        }
    }

    @ViewBuilder
    private var friendsContent: some View {
        if vm.friendsActivity.isEmpty {
            if vm.isLoadingFriends {
                centeredSpinner
            } else if let err = vm.friendsError {
                errorBlock(title: "Не удалось загрузить друзей", message: err) {
                    refreshActiveTab()
                }
            } else if auth.profile == nil {
                centeredText("Авторизуйтесь, чтобы увидеть ленту друзей.")
            } else {
                centeredText("Пока никого нет в списке друзей.")
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(vm.friendsActivity) { activity in
                    FriendActivityCard(activity: activity, onOpenAnime: onOpenAnime)
                }
            }
        }
    }

    @ViewBuilder
    private func forumContent(state: ForumFeedState, tab: SocialTab) -> some View {
        if state.topics.isEmpty {
            if state.isLoading {
                centeredSpinner
            } else if let err = state.error {
                errorBlock(title: emptyTitle(for: tab), message: err) {
                    refreshActiveTab()
                }
            } else {
                centeredText(emptyMessage(for: tab))
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(state.topics, id: \.id) { topic in
                    TopicCard(topic: topic) { selectedTopic = topic }
                }
                loadMoreFooter(state: state, tab: tab)
            }
        }
    }

    @ViewBuilder
    private func loadMoreFooter(state: ForumFeedState, tab: SocialTab) -> some View {
        if state.isLoadingMore {
            HStack {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            }
            .padding(.vertical, 16)
        } else if state.canLoadMore {
            Button {
                Task {
                    guard let config = auth.configuration else { return }
                    await vm.loadMoreForumFeed(configuration: config, tab: tab)
                }
            } label: {
                Text("Загрузить ещё")
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
            .padding(.top, 6)
        }
    }

    // MARK: - Labels

    private func emptyTitle(for tab: SocialTab) -> String {
        switch tab {
        case .reviews:     return "Не удалось загрузить обзоры"
        case .discussions: return "Не удалось загрузить ленту"
        case .friends:     return "Не удалось загрузить"
        }
    }

    private func emptyMessage(for tab: SocialTab) -> String {
        switch tab {
        case .reviews:     return "Обзоров пока нет."
        case .discussions: return "В ленте пока пусто."
        case .friends:     return "Нет друзей."
        }
    }

    // MARK: - States

    private var centeredSpinner: some View {
        HStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .padding(.vertical, 80)
    }

    private func centeredText(_ text: String) -> some View {
        Text(text)
            .font(.dsBody(13))
            .foregroundStyle(theme.fg3)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 80)
    }

    private func errorBlock(title: String, message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.dsTitle(16, weight: .semibold))
                .foregroundStyle(theme.fg)
            Text(message)
                .font(.dsBody(12))
                .foregroundStyle(theme.fg3)
                .multilineTextAlignment(.center)
            Button("Повторить", action: retry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    // MARK: - Load helpers

    private func loadActiveTab() async {
        guard let config = auth.configuration else { return }
        switch vm.selectedTab {
        case .friends:
            guard let userId = auth.profile?.id else { return }
            await vm.reloadFriends(configuration: config, userId: userId)
        case .discussions, .reviews:
            await vm.reloadForumFeed(configuration: config, tab: vm.selectedTab)
        }
    }

    private func refreshActiveTab() {
        Task {
            guard let config = auth.configuration else { return }
            switch vm.selectedTab {
            case .friends:
                guard let userId = auth.profile?.id else { return }
                await vm.reloadFriends(configuration: config, userId: userId, forceRefresh: true)
            case .discussions, .reviews:
                await vm.reloadForumFeed(configuration: config, tab: vm.selectedTab, forceRefresh: true)
            }
        }
    }
}
