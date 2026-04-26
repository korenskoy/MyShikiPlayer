//
//  SocialViewModel.swift
//  MyShikiPlayer
//
//  Model for SocialView: three tabs (friends / discussions / reviews).
//  Per-forum feed state so switching tabs doesn't lose data.
//

import Foundation
import Combine

enum SocialTab: String, CaseIterable, Identifiable {
    case friends
    case discussions
    case reviews
    var id: String { rawValue }
    var title: String {
        switch self {
        case .friends:     return "Друзья"
        case .discussions: return "Обсуждения"
        case .reviews:     return "Обзоры"
        }
    }
    /// Shikimori forum code for tabs tied to /api/topics.
    /// Shikimori only accepts a specific list of values (see API 422 response)
    /// — reviews use `critiques`, not `reviews`.
    var forum: String? {
        switch self {
        case .friends:     return nil
        case .discussions: return "animanga"
        case .reviews:     return "critiques"
        }
    }
}

/// State for a single forum feed (discussions, reviews). Kept separate per
/// tab so pagination and scroll position don't get mixed up.
struct ForumFeedState: Equatable {
    var topics: [Topic] = []
    var page: Int = 1
    var canLoadMore: Bool = true
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var error: String?
}

@MainActor
final class SocialViewModel: ObservableObject {
    @Published var selectedTab: SocialTab = .friends

    @Published var discussions = ForumFeedState()
    @Published var reviews = ForumFeedState()

    @Published private(set) var friendsActivity: [SocialRepo.FriendActivity] = []
    @Published private(set) var isLoadingFriends: Bool = false
    @Published private(set) var friendsError: String?

    private let pageSize = 30

    // MARK: - Forum feeds (discussions / reviews)

    func reloadForumFeed(
        configuration: ShikimoriConfiguration,
        tab: SocialTab,
        forceRefresh: Bool = false
    ) async {
        guard let forum = tab.forum else { return }
        var state = stateFor(tab: tab)
        if !forceRefresh, let cached = SocialRepo.shared.cachedFeed(forum: forum, allowStale: true) {
            state.topics = cached
        } else {
            state.isLoading = true
        }
        state.error = nil
        state.page = 1
        state.canLoadMore = true
        apply(state, to: tab)

        do {
            let topics = try await SocialRepo.shared.feed(
                configuration: configuration,
                forum: forum,
                forceRefresh: forceRefresh
            )
            state.topics = topics
            state.canLoadMore = topics.count >= pageSize
        } catch {
            if state.topics.isEmpty {
                state.error = error.localizedDescription
            }
        }
        state.isLoading = false
        apply(state, to: tab)
    }

    func loadMoreForumFeed(configuration: ShikimoriConfiguration, tab: SocialTab) async {
        guard let forum = tab.forum else { return }
        var state = stateFor(tab: tab)
        guard state.canLoadMore, !state.isLoadingMore, !state.isLoading else { return }
        state.isLoadingMore = true
        apply(state, to: tab)

        let nextPage = state.page + 1
        do {
            let more = try await SocialRepo.shared.feedPage(
                configuration: configuration,
                forum: forum,
                page: nextPage
            )
            let existing = Set(state.topics.map(\.id))
            let fresh = more.filter { !existing.contains($0.id) }
            state.topics.append(contentsOf: fresh)
            state.page = nextPage
            state.canLoadMore = more.count >= pageSize
        } catch {
            NetworkLogStore.shared.logAppError(
                "social_load_more_failed forum=\(forum) page=\(nextPage) err=\(error.localizedDescription)"
            )
        }
        state.isLoadingMore = false
        apply(state, to: tab)
    }

    private func stateFor(tab: SocialTab) -> ForumFeedState {
        switch tab {
        case .discussions: return discussions
        case .reviews:     return reviews
        case .friends:     return ForumFeedState()
        }
    }

    private func apply(_ state: ForumFeedState, to tab: SocialTab) {
        switch tab {
        case .discussions: discussions = state
        case .reviews:     reviews = state
        case .friends:     break
        }
    }

    // MARK: - Friends activity

    func reloadFriends(
        configuration: ShikimoriConfiguration,
        userId: Int,
        forceRefresh: Bool = false
    ) async {
        if !forceRefresh, let cached = SocialRepo.shared.cachedFriendsActivity(userId: userId, allowStale: true) {
            friendsActivity = cached
        } else {
            isLoadingFriends = true
        }
        friendsError = nil
        do {
            friendsActivity = try await SocialRepo.shared.friendsActivity(
                configuration: configuration,
                userId: userId,
                forceRefresh: forceRefresh
            )
        } catch {
            if friendsActivity.isEmpty {
                friendsError = error.localizedDescription
            }
        }
        isLoadingFriends = false
    }
}

@MainActor
final class TopicDetailViewModel: ObservableObject {
    @Published private(set) var topic: Topic?
    @Published private(set) var comments: [TopicComment] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    let topicId: Int

    init(topicId: Int, seed: Topic? = nil) {
        self.topicId = topicId
        self.topic = seed
    }

    func load(configuration: ShikimoriConfiguration) async {
        if let cached = SocialRepo.shared.cachedTopic(id: topicId, allowStale: true) {
            topic = cached
        }
        if let cachedComments = SocialRepo.shared.cachedComments(topicId: topicId, allowStale: true) {
            comments = cachedComments
        } else {
            isLoading = true
        }
        errorMessage = nil

        async let topicResult = SocialRepo.shared.topic(configuration: configuration, id: topicId)
        async let commentsResult = SocialRepo.shared.comments(configuration: configuration, topicId: topicId)

        do {
            topic = try await topicResult
        } catch {
            if topic == nil {
                errorMessage = error.localizedDescription
            }
        }
        do {
            comments = try await commentsResult
        } catch {
            NetworkLogStore.shared.logAppError(
                "social_comments_failed topic=\(topicId) err=\(error.localizedDescription)"
            )
        }
        isLoading = false
    }
}
