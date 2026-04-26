//
//  CalendarRepo.swift
//  MyShikiPlayer
//
//  Cache for /api/calendar. TTL 30 minutes, single key — the schedule is
//  global. Request dedup in case the user quickly leaves/returns to the
//  screen.
//

import Foundation

@MainActor
final class CalendarRepo {
    static let shared = CalendarRepo()

    private static let diskFilename = "calendar.json"

    private init() {
        let loaded = DiskBackup.load(into: cache, filename: Self.diskFilename)
        if loaded > 0 {
            NetworkLogStore.shared.logUIEvent("calendar_repo_disk_loaded count=\(loaded)")
        }
        // The schedule does not depend on user-rate/favorite — only listen for wipe.
        CacheEvents.observeClearAll { [weak self] in
            self?.invalidate()
        }
    }

    private let cache = TTLCache<String, [CalendarEntry]>(ttl: 30 * 60)
    private var pending: Task<[CalendarEntry], Error>?
    private static let cacheKey = "calendar"

    func cached(allowStale: Bool = false) -> [CalendarEntry]? {
        allowStale ? cache.getStale(Self.cacheKey) : cache.get(Self.cacheKey)
    }

    func entries(
        configuration: ShikimoriConfiguration,
        forceRefresh: Bool = false
    ) async throws -> [CalendarEntry] {
        if !forceRefresh, let cached = cache.get(Self.cacheKey) {
            NetworkLogStore.shared.logUIEvent("calendar_repo_hit count=\(cached.count)")
            return cached
        }
        if let existing = pending { return try await existing.value }

        let task = Task<[CalendarEntry], Error> { [weak self] in
            defer { self?.pending = nil }
            let rest = ShikimoriRESTClient(configuration: configuration)
            let entries = try await rest.calendar()
            self?.cache.set(entries, for: Self.cacheKey)
            NetworkLogStore.shared.logUIEvent("calendar_repo_loaded count=\(entries.count)")
            return entries
        }
        pending = task
        return try await task.value
    }

    func invalidate() {
        cache.invalidate(Self.cacheKey)
        pending?.cancel()
        pending = nil
    }
}
