//
//  CacheNotifications.swift
//  MyShikiPlayer
//
//  Pub/sub for cache invalidation (Iter 4). Previously mutation sites
//  (ViewModels, Settings) called `Repo.shared.invalidate(...)` directly,
//  tightly coupling business logic to the list of repositories. Now the
//  mutation site just posts an event, and each repo decides how to react.
//
//  Subscriptions are registered in the repo singleton's `init()`;
//  unsubscription is not needed — repos live for the entire app lifetime.
//

import Foundation

extension Notification.Name {
    /// user_rate changed (status, score, episode count).
    /// userInfo: `[animeIdKey: Int, userIdKey: Int]`
    static let cacheUserRateDidChange = Notification.Name("mshp.cache.userRateDidChange")

    /// user_rate fully removed (title taken out of the user's list).
    /// userInfo: `[animeIdKey: Int, userIdKey: Int]`
    /// Note: a remove also implicitly triggers `cacheUserRateDidChange` so
    /// repos that only care about "something changed" keep working.
    static let cacheUserRateRemoved = Notification.Name("mshp.cache.userRateRemoved")

    /// Favorite toggled.
    /// userInfo: `[animeIdKey: Int, userIdKey: Int]`
    static let cacheFavoriteDidToggle = Notification.Name("mshp.cache.favoriteDidToggle")

    /// Global wipe (Settings → "Reset cache").
    static let cacheShouldClearAll = Notification.Name("mshp.cache.shouldClearAll")
}

enum CacheEvents {
    static let animeIdKey = "animeId"
    static let userIdKey = "userId"
    static let rateIdKey = "rateId"
    static let statusKey = "status"
    static let scoreKey = "score"
    static let episodesKey = "episodes"
    static let updatedAtKey = "updatedAt"

    /// Snapshot of the new user_rate state attached to `.cacheUserRateDidChange`
    /// when the publisher knows the post-mutation values. Lets list-level
    /// subscribers (Library) update their in-memory rows without a refetch.
    /// Absent (nil) on the implicit `.didChange` posted from `postUserRateRemoved`.
    struct UserRatePayload {
        let rateId: Int
        let status: String
        let score: Int
        let episodes: Int
        let updatedAt: Date?
    }

    /// Push: user-rate (status / score / episodes) changed for a title.
    /// Subscribers: AnimeDetailRepo (by animeId), HomeSectionsRepo (by userId),
    /// ProfileRepo (stats shift — by userId), AnimeListViewModel (in-place row update).
    /// Pass `payload` when the new rate state is known so list-level subscribers
    /// can avoid a refetch.
    static func postUserRateChanged(
        animeId: Int,
        userId: Int,
        payload: UserRatePayload? = nil
    ) {
        var info: [String: Any] = [animeIdKey: animeId, userIdKey: userId]
        if let payload {
            info[rateIdKey] = payload.rateId
            info[statusKey] = payload.status
            info[scoreKey] = payload.score
            info[episodesKey] = payload.episodes
            if let updatedAt = payload.updatedAt {
                info[updatedAtKey] = updatedAt
            }
        }
        NotificationCenter.default.post(
            name: .cacheUserRateDidChange,
            object: nil,
            userInfo: info
        )
    }

    /// Push: user_rate fully removed. Posts both the dedicated `.removed`
    /// event (so list-level subscribers can drop the row) AND the generic
    /// `.didChange` event (so existing repos that only care about "changed"
    /// keep invalidating).
    static func postUserRateRemoved(animeId: Int, userId: Int) {
        let info: [String: Any] = [animeIdKey: animeId, userIdKey: userId]
        NotificationCenter.default.post(name: .cacheUserRateRemoved, object: nil, userInfo: info)
        NotificationCenter.default.post(name: .cacheUserRateDidChange, object: nil, userInfo: info)
    }

    /// Push: favorite toggled.
    /// Subscribers: AnimeDetailRepo (detail.favoured), HomeSectionsRepo,
    /// ProfileRepo (favourites list).
    static func postFavoriteToggled(animeId: Int, userId: Int) {
        NotificationCenter.default.post(
            name: .cacheFavoriteDidToggle,
            object: nil,
            userInfo: [animeIdKey: animeId, userIdKey: userId]
        )
    }

    /// Push: global wipe — all repos clear in-memory + disk.
    static func postClearAllCaches() {
        NotificationCenter.default.post(name: .cacheShouldClearAll, object: nil)
    }

    // MARK: - Subscription helpers

    /// Subscribe to user-rate / favorite events. The callback receives
    /// `(animeId, userId)`. Called on the main queue.
    @MainActor
    static func observeAnimeMutation(
        names: [Notification.Name] = [.cacheUserRateDidChange, .cacheFavoriteDidToggle],
        handler: @escaping @MainActor (_ animeId: Int, _ userId: Int) -> Void
    ) {
        for name in names {
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { notif in
                guard let animeId = notif.userInfo?[animeIdKey] as? Int,
                      let userId = notif.userInfo?[userIdKey] as? Int
                else { return }
                Task { @MainActor in handler(animeId, userId) }
            }
        }
    }

    /// Subscribe to user-rate change with an optional payload describing the
    /// new state. Payload is `nil` when the publisher didn't pass one (e.g.
    /// the implicit `.didChange` from `postUserRateRemoved`).
    /// Invoked on the main queue.
    @MainActor
    static func observeUserRateChanged(
        handler: @escaping @MainActor (_ animeId: Int, _ userId: Int, _ payload: UserRatePayload?) -> Void
    ) {
        NotificationCenter.default.addObserver(
            forName: .cacheUserRateDidChange,
            object: nil,
            queue: .main
        ) { notif in
            guard let animeId = notif.userInfo?[animeIdKey] as? Int,
                  let userId = notif.userInfo?[userIdKey] as? Int
            else { return }
            let payload: UserRatePayload? = {
                guard let rateId = notif.userInfo?[rateIdKey] as? Int,
                      let status = notif.userInfo?[statusKey] as? String,
                      let score = notif.userInfo?[scoreKey] as? Int,
                      let episodes = notif.userInfo?[episodesKey] as? Int
                else { return nil }
                return UserRatePayload(
                    rateId: rateId,
                    status: status,
                    score: score,
                    episodes: episodes,
                    updatedAt: notif.userInfo?[updatedAtKey] as? Date
                )
            }()
            Task { @MainActor in handler(animeId, userId, payload) }
        }
    }

    /// Subscribe to user-rate removal. The callback receives `(animeId, userId)`
    /// and is invoked on the main queue.
    @MainActor
    static func observeUserRateRemoved(
        handler: @escaping @MainActor (_ animeId: Int, _ userId: Int) -> Void
    ) {
        NotificationCenter.default.addObserver(
            forName: .cacheUserRateRemoved,
            object: nil,
            queue: .main
        ) { notif in
            guard let animeId = notif.userInfo?[animeIdKey] as? Int,
                  let userId = notif.userInfo?[userIdKey] as? Int
            else { return }
            Task { @MainActor in handler(animeId, userId) }
        }
    }

    /// Subscribe to "clear all". The callback is invoked on the main queue.
    @MainActor
    static func observeClearAll(handler: @escaping @MainActor () -> Void) {
        NotificationCenter.default.addObserver(
            forName: .cacheShouldClearAll,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in handler() }
        }
    }
}
