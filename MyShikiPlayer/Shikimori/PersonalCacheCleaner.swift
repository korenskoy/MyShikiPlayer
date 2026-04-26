//
//  PersonalCacheCleaner.swift
//  MyShikiPlayer
//
//  Drops every personal cache that depends on a logged-in Shikimori session
//  (history, library, user_rates, watch progress, profile snapshots, social
//  feed, anime detail). Kodik tokens, custom hosts, theme, networking-toggle,
//  navigation history, image cache and per-title preferences are intentionally
//  preserved — see feedback_player_resilience and the rules in PLAN-redesign.
//
//  Two callsites only:
//   * `ShikimoriAuthController.markRequiresReauth()` — once, when a refresh
//     fails or the refresh token disappears.
//   * `ShikimoriAuthController.signOut()` — explicit user action.
//

import Foundation

@MainActor
enum PersonalCacheCleaner {
    /// Wipes every personal Shikimori cache. Idempotent and safe to call from
    /// `@MainActor`. Does NOT touch the Keychain — that responsibility stays
    /// with `ShikimoriAuthController.signOut()`.
    static func purge(reason: String) {
        // 1. In-memory + disk-backed repository caches (history, profile,
        //    home-sections, social, anime detail, kodik catalog). All repos
        //    subscribe to `cacheShouldClearAll`; this single post wipes them.
        //    `WatchProgressStore` also listens here and flushes its dict.
        CacheEvents.postClearAllCaches()

        // 2. Watch progress on disk (resume positions per shikimoriId).
        UserDefaults.standard.removeObject(forKey: "watchProgressStore.records")

        // 3. Watch history journal (~/Library/Caches/.../watch-history.json).
        WatchHistoryStore.shared.clearAll()

        // 4. Library list cache (per-userId entries `animeList.cache.v2.*`).
        purgeLibraryListCache()

        // 5. Memoised GraphQL `currentUser` query shape — tied to a user.
        UserDefaults.standard.removeObject(forKey: "shikimori.gql.currentUserQuery")

        NetworkLogStore.shared.logUIEvent("personal_cache_purged reason=\(reason)")
    }

    private static func purgeLibraryListCache() {
        let prefix = "animeList.cache.v2."
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys
        for key in keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
