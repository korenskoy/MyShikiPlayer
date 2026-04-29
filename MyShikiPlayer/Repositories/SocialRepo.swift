//
//  SocialRepo.swift
//  MyShikiPlayer
//
//  Social feed cache: topic feed (forum=animanga), individual topics, and
//  comments. Three distinct TTL maps with different keys.
//

import Foundation

@MainActor
final class SocialRepo {
    static let shared = SocialRepo()

    private static let diskFilenameFeed = "social-feed.json"
    private static let diskFilenameTopic = "social-topic.json"
    private static let diskFilenameComments = "social-comments.json"
    private static let diskFilenameFriends = "social-friends.json"

    private init() {
        let feed = DiskBackup.load(into: feedCache, filename: Self.diskFilenameFeed)
        let topic = DiskBackup.load(into: topicCache, filename: Self.diskFilenameTopic)
        let comments = DiskBackup.load(into: commentsCache, filename: Self.diskFilenameComments)
        let friends = DiskBackup.load(into: friendsActivityCache, filename: Self.diskFilenameFriends)
        let total = feed + topic + comments + friends
        if total > 0 {
            NetworkLogStore.shared.logUIEvent(
                "social_repo_disk_loaded feed=\(feed) topic=\(topic) comments=\(comments) friends=\(friends)"
            )
        }
        // The social feed does not depend on user-rate/favorite — only listen for wipe.
        CacheEvents.observeClearAll { [weak self] in
            self?.invalidateAll()
        }
    }

    /// Friend activity card: the friend plus their most recent history events.
    struct FriendActivity: Equatable, Identifiable, Codable {
        let friend: UserFriend
        let entries: [UserHistoryEntry]
        var id: Int { friend.id }
    }

    private let feedCache = TTLCache<String, [Topic]>(ttl: 5 * 60)
    private let topicCache = TTLCache<Int, Topic>(ttl: 10 * 60)
    private let commentsCache = TTLCache<Int, [TopicComment]>(ttl: 10 * 60)
    private let friendsActivityCache = TTLCache<Int, [FriendActivity]>(ttl: 5 * 60)

    private var pendingFeed: [String: Task<[Topic], Error>] = [:]
    private var pendingTopic: [Int: Task<Topic, Error>] = [:]
    private var pendingComments: [Int: Task<[TopicComment], Error>] = [:]
    private var pendingFriendsActivity: [Int: Task<[FriendActivity], Error>] = [:]

    // MARK: - Feed

    func cachedFeed(forum: String, allowStale: Bool = false) -> [Topic]? {
        allowStale ? feedCache.getStale(forum) : feedCache.get(forum)
    }

    func feed(
        configuration: ShikimoriConfiguration,
        forum: String = "animanga",
        forceRefresh: Bool = false
    ) async throws -> [Topic] {
        if !forceRefresh, let cached = feedCache.get(forum) {
            NetworkLogStore.shared.logUIEvent("social_feed_hit forum=\(forum) count=\(cached.count)")
            return cached
        }
        if let existing = pendingFeed[forum] { return try await existing.value }

        let task = Task<[Topic], Error> { [weak self] in
            defer { self?.pendingFeed.removeValue(forKey: forum) }
            let rest = ShikimoriRESTClient(configuration: configuration)
            let topics = try await rest.topics(forum: forum, limit: 30)
            self?.feedCache.set(topics, for: forum)
            if let strongSelf = self {
                DiskBackup.save(cache: strongSelf.feedCache, filename: Self.diskFilenameFeed)
            }
            NetworkLogStore.shared.logUIEvent("social_feed_loaded forum=\(forum) count=\(topics.count)")
            return topics
        }
        pendingFeed[forum] = task
        return try await task.value
    }

    func invalidateFeed() {
        feedCache.invalidateAll()
        pendingFeed.values.forEach { $0.cancel() }
        pendingFeed.removeAll()
        DiskBackup.remove(filename: Self.diskFilenameFeed)
    }

    /// Load the next page of the feed (not cached — pagination is always
    /// fresh). The caller appends the result to the existing array.
    func feedPage(
        configuration: ShikimoriConfiguration,
        forum: String = "animanga",
        page: Int
    ) async throws -> [Topic] {
        let rest = ShikimoriRESTClient(configuration: configuration)
        let topics = try await rest.topics(forum: forum, limit: 30, page: page)
        NetworkLogStore.shared.logUIEvent(
            "social_feed_page forum=\(forum) page=\(page) count=\(topics.count)"
        )
        return topics
    }

    // MARK: - Friends activity

    func cachedFriendsActivity(userId: Int, allowStale: Bool = false) -> [FriendActivity]? {
        allowStale ? friendsActivityCache.getStale(userId) : friendsActivityCache.get(userId)
    }

    /// Builds activity from the friend list. Concurrently fetches friends +
    /// the history of the first N. If there are no friends — returns an
    /// empty list.
    func friendsActivity(
        configuration: ShikimoriConfiguration,
        userId: Int,
        forceRefresh: Bool = false
    ) async throws -> [FriendActivity] {
        if !forceRefresh, let cached = friendsActivityCache.get(userId) {
            NetworkLogStore.shared.logUIEvent(
                "social_friends_hit user=\(userId) count=\(cached.count)"
            )
            return cached
        }
        if let existing = pendingFriendsActivity[userId] { return try await existing.value }

        let task = Task<[FriendActivity], Error> { [weak self] in
            defer { self?.pendingFriendsActivity.removeValue(forKey: userId) }
            let rest = ShikimoriRESTClient(configuration: configuration)
            let friends = try await rest.userFriends(id: userId)
            // Cap at 10 friends to avoid spamming the API — the rest will
            // land in "more" later (once we design pagination).
            let capped = Array(friends.prefix(10))
            guard !capped.isEmpty else {
                self?.friendsActivityCache.set([], for: userId)
                if let strongSelf = self {
                    DiskBackup.save(
                        cache: strongSelf.friendsActivityCache,
                        filename: Self.diskFilenameFriends
                    )
                }
                return []
            }

            // Per friend — a separate history request. In parallel, but
            // strictly capped at 10 to avoid 429s. Shikimori does not impose
            // aggressive limits on /history, but better safe than sorry.
            let activities = await withTaskGroup(of: FriendActivity?.self) { group in
                for friend in capped {
                    group.addTask {
                        do {
                            let history = try await rest.userHistory(
                                id: friend.id,
                                targetType: "Anime",
                                limit: 5
                            )
                            guard !history.isEmpty else { return nil }
                            return FriendActivity(friend: friend, entries: history)
                        } catch {
                            await MainActor.run {
                                NetworkLogStore.shared.logAppError(
                                    "social_friend_history_failed user=\(friend.id) err=\(error.localizedDescription)"
                                )
                            }
                            return nil
                        }
                    }
                }
                var result: [FriendActivity] = []
                for await item in group {
                    if let item { result.append(item) }
                }
                return result
            }
            // Sort by the most recent event date — fresh ones on top.
            let sorted = activities.sorted { a, b in
                (a.entries.first?.createdAt ?? .distantPast) > (b.entries.first?.createdAt ?? .distantPast)
            }
            self?.friendsActivityCache.set(sorted, for: userId)
            if let strongSelf = self {
                DiskBackup.save(
                    cache: strongSelf.friendsActivityCache,
                    filename: Self.diskFilenameFriends
                )
            }
            NetworkLogStore.shared.logUIEvent(
                "social_friends_loaded user=\(userId) friends=\(friends.count) with_activity=\(sorted.count)"
            )
            return sorted
        }
        pendingFriendsActivity[userId] = task
        return try await task.value
    }

    // MARK: - Topic

    func cachedTopic(id: Int, allowStale: Bool = false) -> Topic? {
        allowStale ? topicCache.getStale(id) : topicCache.get(id)
    }

    func topic(
        configuration: ShikimoriConfiguration,
        id: Int,
        forceRefresh: Bool = false
    ) async throws -> Topic {
        if !forceRefresh, let cached = topicCache.get(id) {
            return cached
        }
        if let existing = pendingTopic[id] { return try await existing.value }

        let task = Task<Topic, Error> { [weak self] in
            defer { self?.pendingTopic.removeValue(forKey: id) }
            let rest = ShikimoriRESTClient(configuration: configuration)
            let topic = try await rest.topic(id: id)
            self?.topicCache.set(topic, for: id)
            if let strongSelf = self {
                DiskBackup.save(cache: strongSelf.topicCache, filename: Self.diskFilenameTopic)
            }
            return topic
        }
        pendingTopic[id] = task
        return try await task.value
    }

    // MARK: - Comments

    func cachedComments(topicId: Int, allowStale: Bool = false) -> [TopicComment]? {
        allowStale ? commentsCache.getStale(topicId) : commentsCache.get(topicId)
    }

    /// Loads a single page of comments without touching the cache (the cache
    /// only holds page 1 — the most recent batch). Used by `loadMore` in the
    /// topic VM to walk further into the past.
    func commentsPage(
        configuration: ShikimoriConfiguration,
        topicId: Int,
        page: Int
    ) async throws -> [TopicComment] {
        let rest = ShikimoriRESTClient(configuration: configuration)
        let comments = try await rest.comments(
            commentableType: "Topic",
            commentableId: topicId,
            limit: 30,
            page: page
        )
        NetworkLogStore.shared.logUIEvent(
            "social_comments_page topic=\(topicId) page=\(page) count=\(comments.count)"
        )
        return comments
    }

    func comments(
        configuration: ShikimoriConfiguration,
        topicId: Int,
        forceRefresh: Bool = false
    ) async throws -> [TopicComment] {
        if !forceRefresh, let cached = commentsCache.get(topicId) {
            return cached
        }
        if let existing = pendingComments[topicId] { return try await existing.value }

        let task = Task<[TopicComment], Error> { [weak self] in
            defer { self?.pendingComments.removeValue(forKey: topicId) }
            let rest = ShikimoriRESTClient(configuration: configuration)
            let comments = try await rest.comments(
                commentableType: "Topic",
                commentableId: topicId,
                limit: 30
            )
            self?.commentsCache.set(comments, for: topicId)
            if let strongSelf = self {
                DiskBackup.save(cache: strongSelf.commentsCache, filename: Self.diskFilenameComments)
            }
            NetworkLogStore.shared.logUIEvent(
                "social_comments_loaded topic=\(topicId) count=\(comments.count)"
            )
            return comments
        }
        pendingComments[topicId] = task
        return try await task.value
    }

    func invalidateAll() {
        feedCache.invalidateAll()
        topicCache.invalidateAll()
        commentsCache.invalidateAll()
        friendsActivityCache.invalidateAll()
        pendingFeed.values.forEach { $0.cancel() }
        pendingTopic.values.forEach { $0.cancel() }
        pendingComments.values.forEach { $0.cancel() }
        pendingFriendsActivity.values.forEach { $0.cancel() }
        pendingFeed.removeAll()
        pendingTopic.removeAll()
        pendingComments.removeAll()
        pendingFriendsActivity.removeAll()
        DiskBackup.remove(filename: Self.diskFilenameFeed)
        DiskBackup.remove(filename: Self.diskFilenameTopic)
        DiskBackup.remove(filename: Self.diskFilenameComments)
        DiskBackup.remove(filename: Self.diskFilenameFriends)
    }
}
