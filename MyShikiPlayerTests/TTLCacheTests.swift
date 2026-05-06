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
}
