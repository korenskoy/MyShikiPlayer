//
//  SocialNavigationState.swift
//  MyShikiPlayer
//
//  Shared navigation state for the Social branch. Owned by AppShellView so
//  that the global browser-style history (NavigationHistoryStore) can
//  read/write it on goBack/goForward; SocialView mutates the same instance
//  when the user picks a tab or opens a topic.
//

import Foundation
import Combine

@MainActor
final class SocialNavigationState: ObservableObject {
    @Published var selectedTab: SocialTab = .friends

    /// Fully-loaded `Topic` from the feed card, when the user opens it
    /// directly. Restored from history (where we only have `id`+`title`)
    /// uses `restoredTopicId` instead — the detail VM re-fetches by id.
    @Published var openedTopicSeed: Topic?

    /// Set when a topic is restored from history without a Topic struct in
    /// memory. `TopicDetailView` opens by id and the VM loads the full Topic
    /// from the API.
    @Published var restoredTopicId: Int?
    @Published var restoredTopicTitle: String?

    /// True iff a topic is on screen (either via seed or via id-restore).
    var isTopicOpen: Bool {
        openedTopicSeed != nil || restoredTopicId != nil
    }

    var openedTopicId: Int? {
        openedTopicSeed?.id ?? restoredTopicId
    }

    var openedTopicTitle: String? {
        openedTopicSeed?.topicTitle ?? restoredTopicTitle
    }

    func openTopic(_ topic: Topic) {
        restoredTopicId = nil
        restoredTopicTitle = nil
        openedTopicSeed = topic
    }

    func restoreTopic(id: Int, title: String?) {
        openedTopicSeed = nil
        restoredTopicId = id
        restoredTopicTitle = title
    }

    func closeTopic() {
        openedTopicSeed = nil
        restoredTopicId = nil
        restoredTopicTitle = nil
    }
}
