//
//  CacheNotifications.swift
//  MyShikiPlayer
//
//  Pub/sub for cache invalidation (Iter 4). Previously mutation sites
//  (ViewModels, Settings) called `Repo.shared.invalidate(...)` directly,
//  tightly coupling business logic to the list of repositories. Now the
//  mutation site just posts an event, and each repo decides how to react.
//
//  Subscription rule: every `observe*` helper returns an observer token.
//  A subscriber whose lifetime is shorter than the app's (view models,
//  per-session stores) MUST retain the token — the easiest way is to keep a
//  `CacheObserverBag` property and feed tokens into it. Otherwise every
//  re-creation leaks another permanent block observer and each cache event
//  fans out to N dead subscribers. Only true singletons (`Repo.shared`) may
//  discard the token, since they never go away.
//

import Foundation

extension Notification.Name {
    /// user_rate changed (status, score, episode count).
    /// Carries a `CacheEvents.MutationPayload`; read it with
    /// `CacheEvents.mutationPayload(from:)`. Same for the two below.
    static let cacheUserRateDidChange = Notification.Name("mshp.cache.userRateDidChange")

    /// user_rate fully removed (title taken out of the user's list).
    /// Note: a remove also implicitly triggers `cacheUserRateDidChange` so
    /// repos that only care about "something changed" keep working.
    static let cacheUserRateRemoved = Notification.Name("mshp.cache.userRateRemoved")

    /// Favorite toggled.
    static let cacheFavoriteDidToggle = Notification.Name("mshp.cache.favoriteDidToggle")

    /// Global wipe (Settings → "Reset cache").
    static let cacheShouldClearAll = Notification.Name("mshp.cache.shouldClearAll")
}

/// Keeps cache-event observer tokens alive for as long as its owner lives and
/// unregisters them on dealloc. Saves every short-lived subscriber from writing
/// a `deinit` that would have to reach into main-actor state (`deinit` is not
/// actor-isolated).
///
/// `@unchecked Sendable`: `tokens` is populated once, from the owner's `init`,
/// and afterwards only read by `deinit`. `removeObserver` is thread-safe.
final class CacheObserverBag: @unchecked Sendable {
    private var tokens: [NSObjectProtocol] = []

    func add(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    func add(_ newTokens: [NSObjectProtocol]) {
        tokens.append(contentsOf: newTokens)
    }

    deinit {
        let center = NotificationCenter.default
        for token in tokens { center.removeObserver(token) }
    }
}

enum CacheEvents {
    /// Snapshot of the new user_rate state attached to `.cacheUserRateDidChange`
    /// when the publisher knows the post-mutation values. Lets list-level
    /// subscribers (Library) update their in-memory rows without a refetch.
    /// Absent (nil) on the implicit `.didChange` posted from `postUserRateRemoved`.
    struct UserRatePayload: Sendable {
        let rateId: Int
        let status: String
        let score: Int
        let episodes: Int
        let updatedAt: Date?
    }

    /// Everything an anime-scoped cache event carries. The notification holds
    /// exactly one of these instead of a `[String: Any]` bag, so publishers and
    /// subscribers agree at compile time.
    struct MutationPayload: Sendable {
        let animeId: Int
        let userId: Int
        let userRate: UserRatePayload?
    }

    /// The single `userInfo` slot. Private on purpose — nothing outside this
    /// file should reach into the dictionary; use `mutationPayload(from:)`.
    private static let payloadKey = "mshp.cache.payload"

    /// Typed read of a cache-event notification. This is the only place in the
    /// app that touches NotificationCenter's untyped payload.
    static func mutationPayload(from notification: Notification) -> MutationPayload? {
        notification.userInfo?[payloadKey] as? MutationPayload
    }

    private static func post(_ name: Notification.Name, _ payload: MutationPayload) {
        NotificationCenter.default.post(
            name: name,
            object: nil,
            userInfo: [payloadKey: payload]
        )
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
        post(
            .cacheUserRateDidChange,
            MutationPayload(animeId: animeId, userId: userId, userRate: payload)
        )
    }

    /// Push: user_rate fully removed. Posts both the dedicated `.removed`
    /// event (so list-level subscribers can drop the row) AND the generic
    /// `.didChange` event (so existing repos that only care about "changed"
    /// keep invalidating).
    static func postUserRateRemoved(animeId: Int, userId: Int) {
        let payload = MutationPayload(animeId: animeId, userId: userId, userRate: nil)
        post(.cacheUserRateRemoved, payload)
        post(.cacheUserRateDidChange, payload)
    }

    /// Push: favorite toggled.
    /// Subscribers: AnimeDetailRepo (detail.favoured), HomeSectionsRepo,
    /// ProfileRepo (favourites list).
    static func postFavoriteToggled(animeId: Int, userId: Int) {
        post(
            .cacheFavoriteDidToggle,
            MutationPayload(animeId: animeId, userId: userId, userRate: nil)
        )
    }

    /// Push: global wipe — all repos clear in-memory + disk.
    static func postClearAllCaches() {
        NotificationCenter.default.post(name: .cacheShouldClearAll, object: nil)
    }

    // MARK: - Subscription helpers

    /// Subscribe to user-rate / favorite events. The callback receives
    /// `(animeId, userId)`. Called on the main queue.
    /// Returns one token per name — keep them unless `self` is a singleton.
    @MainActor
    @discardableResult
    static func observeAnimeMutation(
        names: [Notification.Name] = [.cacheUserRateDidChange, .cacheFavoriteDidToggle],
        handler: @escaping @MainActor (_ animeId: Int, _ userId: Int) -> Void
    ) -> [NSObjectProtocol] {
        return names.map { name in
            return NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { notif in
                guard let payload = mutationPayload(from: notif) else { return }
                Task { @MainActor in handler(payload.animeId, payload.userId) }
            }
        }
    }

    /// Subscribe to user-rate change with an optional payload describing the
    /// new state. Payload is `nil` when the publisher didn't pass one (e.g.
    /// the implicit `.didChange` from `postUserRateRemoved`).
    /// Invoked on the main queue. Returns the observer token — keep it unless
    /// `self` is a singleton.
    @MainActor
    @discardableResult
    static func observeUserRateChanged(
        handler: @escaping @MainActor (_ animeId: Int, _ userId: Int, _ payload: UserRatePayload?) -> Void
    ) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(
            forName: .cacheUserRateDidChange,
            object: nil,
            queue: .main
        ) { notif in
            guard let payload = mutationPayload(from: notif) else { return }
            Task { @MainActor in
                handler(payload.animeId, payload.userId, payload.userRate)
            }
        }
    }

    /// Subscribe to user-rate removal. The callback receives `(animeId, userId)`
    /// and is invoked on the main queue. Returns the observer token — keep it
    /// unless `self` is a singleton.
    @MainActor
    @discardableResult
    static func observeUserRateRemoved(
        handler: @escaping @MainActor (_ animeId: Int, _ userId: Int) -> Void
    ) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(
            forName: .cacheUserRateRemoved,
            object: nil,
            queue: .main
        ) { notif in
            guard let payload = mutationPayload(from: notif) else { return }
            Task { @MainActor in handler(payload.animeId, payload.userId) }
        }
    }

    /// Subscribe to "clear all". The callback is invoked on the main queue.
    /// Returns the observer token — keep it unless `self` is a singleton.
    @MainActor
    @discardableResult
    static func observeClearAll(handler: @escaping @MainActor () -> Void) -> NSObjectProtocol {
        return NotificationCenter.default.addObserver(
            forName: .cacheShouldClearAll,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in handler() }
        }
    }
}
