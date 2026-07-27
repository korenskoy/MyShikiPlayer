//
//  TTLCacheTests.swift
//  MyShikiPlayerTests
//

import Foundation
import Testing
@testable import MyShikiPlayer

@MainActor
@Suite("TTLCache")
struct TTLCacheTests {
    @Test func freshValueAvailableWithinTTL() {
        let cache = TTLCache<Int, String>(ttl: 60)
        cache.set("value", for: 1)
        #expect(cache.get(1) == "value")
        #expect(cache.isStale(1) == false)
        #expect(cache.isEmpty == false)
    }

    @Test func missingKeyReturnsNil() {
        let cache = TTLCache<Int, String>(ttl: 60)
        #expect(cache.get(99) == nil)
        #expect(cache.getStale(99) == nil)
        #expect(cache.isStale(99) == false)
    }

    @Test func staleAccessReturnsExpiredEntry() {
        let cache = TTLCache<Int, String>(ttl: 60)
        // Inject a timestamp from the past so the entry is already expired.
        cache.restore(key: 1, value: "stale", storedAt: Date(timeIntervalSinceNow: -120))
        #expect(cache.get(1) == nil)        // expired → fresh path returns nil
        #expect(cache.getStale(1) == "stale") // SWR path keeps it visible
        #expect(cache.isStale(1) == true)
    }

    @Test func invalidateRemovesEntry() {
        let cache = TTLCache<Int, String>(ttl: 60)
        cache.set("v", for: 1)
        cache.invalidate(1)
        #expect(cache.get(1) == nil)
        #expect(cache.getStale(1) == nil)
    }

    @Test func invalidateAllClearsEverything() {
        let cache = TTLCache<Int, String>(ttl: 60)
        cache.set("a", for: 1)
        cache.set("b", for: 2)
        cache.invalidateAll()
        #expect(cache.isEmpty == true)
        #expect(cache.get(1) == nil)
        #expect(cache.get(2) == nil)
    }

    @Test func setOverwritesAndRefreshesTimestamp() {
        let cache = TTLCache<Int, String>(ttl: 60)
        cache.restore(key: 1, value: "old", storedAt: Date(timeIntervalSinceNow: -120))
        #expect(cache.get(1) == nil) // expired

        // A fresh `set` re-stamps the entry.
        cache.set("new", for: 1)
        #expect(cache.get(1) == "new")
        #expect(cache.isStale(1) == false)
    }

    @Test func allEntriesRoundTrip() {
        let cache = TTLCache<Int, String>(ttl: 60)
        cache.set("a", for: 1)
        cache.set("b", for: 2)

        let dump = cache.allEntries
        #expect(dump.count == 2)

        let restored = TTLCache<Int, String>(ttl: 60)
        for entry in dump {
            restored.restore(key: entry.key, value: entry.value, storedAt: entry.storedAt)
        }
        #expect(restored.get(1) == "a")
        #expect(restored.get(2) == "b")
    }

    // MARK: - Size limit

    @Test func overflowEvictsOldestEntriesFirst() {
        let cache = TTLCache<Int, String>(ttl: 60 * 60, maxEntries: 3)
        let now = Date()
        cache.restore(key: 1, value: "oldest", storedAt: now.addingTimeInterval(-30))
        cache.restore(key: 2, value: "older", storedAt: now.addingTimeInterval(-20))
        cache.restore(key: 3, value: "old", storedAt: now.addingTimeInterval(-10))
        cache.restore(key: 4, value: "newest", storedAt: now)

        #expect(cache.count == 3)
        #expect(cache.getStale(1) == nil)
        #expect(cache.get(2) == "older")
        #expect(cache.get(3) == "old")
        #expect(cache.get(4) == "newest")
    }

    @Test func setNeverGrowsPastTheLimit() {
        let cache = TTLCache<Int, String>(ttl: 60 * 60, maxEntries: 5)
        for index in 0..<50 {
            cache.set("v\(index)", for: index)
        }
        #expect(cache.count == 5)
    }

    @Test func diskRestoreKeepsTheNewestEntriesOnly() {
        // Whole batch is past TTL — the shape of a cold start from a bloated
        // on-disk dump.
        let cache = TTLCache<Int, String>(ttl: 60, maxEntries: 10)
        let base = Date(timeIntervalSinceNow: -3600)
        for index in 0..<40 {
            cache.restore(key: index, value: "v\(index)", storedAt: base.addingTimeInterval(Double(index)))
        }
        #expect(cache.count == 10)
        #expect(cache.getStale(39) == "v39") // survivor, still SWR-readable
        #expect(cache.get(39) == nil)        // …but not fresh
        #expect(cache.getStale(0) == nil)    // evicted
    }

    // MARK: - Stale-while-revalidate vs eviction

    @Test func expiredEntrySurvivesWhileThereIsRoom() {
        let cache = TTLCache<Int, String>(ttl: 60, maxEntries: 2)
        cache.restore(key: 1, value: "stale", storedAt: Date(timeIntervalSinceNow: -600))
        cache.set("fresh", for: 2)

        // Under the limit → expiry alone must not evict.
        #expect(cache.count == 2)
        #expect(cache.get(1) == nil)
        #expect(cache.getStale(1) == "stale")
    }

    @Test func overflowDropsExpiredEntriesBeforeFreshOnes() {
        let cache = TTLCache<Int, String>(ttl: 60, maxEntries: 2)
        cache.restore(key: 1, value: "expired", storedAt: Date(timeIntervalSinceNow: -600))
        cache.restore(key: 2, value: "fresh-old", storedAt: Date(timeIntervalSinceNow: -30))
        cache.set("fresh-new", for: 3)

        #expect(cache.getStale(1) == nil)
        #expect(cache.get(2) == "fresh-old")
        #expect(cache.get(3) == "fresh-new")
    }
}
