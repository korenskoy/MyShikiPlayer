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

    /// Favorite toggled.
    /// userInfo: `[animeIdKey: Int, userIdKey: Int]`
    static let cacheFavoriteDidToggle = Notification.Name("mshp.cache.favoriteDidToggle")

    /// Global wipe (Settings → "Reset cache").
    static let cacheShouldClearAll = Notification.Name("mshp.cache.shouldClearAll")
}

enum CacheEvents {
    static let animeIdKey = "animeId"
    static let userIdKey = "userId"

    /// Push: user-rate (status / score / episodes) changed for a title.
    /// Subscribers: AnimeDetailRepo (by animeId), HomeSectionsRepo (by userId),
    /// ProfileRepo (stats shift — by userId).
    static func postUserRateChanged(animeId: Int, userId: Int) {
        NotificationCenter.default.post(
            name: .cacheUserRateDidChange,
            object: nil,
            userInfo: [animeIdKey: animeId, userIdKey: userId]
        )
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
