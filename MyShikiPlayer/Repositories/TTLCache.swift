//
//  TTLCache.swift
//  MyShikiPlayer
//
//  In-memory key→value cache with TTL. Supports stale-while-revalidate:
//  expired values are NOT removed automatically — they are read via
//  `getStale(_:)`. Regular `get(_:)` returns only fresh values.
//
//  Bounded by `maxEntries`. Eviction is driven purely by overflow, never by
//  age alone: an expired entry is kept for as long as there is room, because
//  SWR needs it to render "what we had" while a refresh is in flight. On
//  overflow the oldest entries by `storedAt` go first.
//

import Foundation

@MainActor
final class TTLCache<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let storedAt: Date
    }

    let ttl: TimeInterval
    /// Upper bound on retained entries. Without it a long session browsing
    /// hundreds of titles grows the map — and the JSON dumped by `DiskBackup`
    /// — without limit.
    let maxEntries: Int
    private var storage: [Key: Entry] = [:]

    init(ttl: TimeInterval, maxEntries: Int = 300) {
        self.ttl = ttl
        self.maxEntries = max(1, maxEntries)
    }

    /// Returns the value only if it is within TTL. Otherwise nil.
    /// An expired entry stays in memory — for a later `getStale`.
    func get(_ key: Key) -> Value? {
        guard let entry = storage[key] else { return nil }
        guard !isExpired(entry) else { return nil }
        return entry.value
    }

    /// Returns the value regardless of freshness (stale-while-revalidate).
    /// The caller usually renders data to the user immediately, and in the
    /// background hits the network via snapshot/refresh to update it.
    func getStale(_ key: Key) -> Value? {
        storage[key]?.value
    }

    /// True if an entry exists but is already past TTL. For diagnostics/logs.
    func isStale(_ key: Key) -> Bool {
        guard let entry = storage[key] else { return false }
        return isExpired(entry)
    }

    func set(_ value: Value, for key: Key) {
        storage[key] = Entry(value: value, storedAt: Date())
        evictOverflow()
    }

    func invalidate(_ key: Key) {
        storage.removeValue(forKey: key)
    }

    func invalidateAll() {
        storage.removeAll()
    }

    var isEmpty: Bool { storage.isEmpty }

    var count: Int { storage.count }

    /// Snapshot of all entries with their timestamps — for disk serialization.
    var allEntries: [(key: Key, value: Value, storedAt: Date)] {
        storage.map { (key: $0.key, value: $0.value.value, storedAt: $0.value.storedAt) }
    }

    /// Restore an entry preserving its original timestamp — for loading from
    /// disk. If the entry is already past TTL, `get(_)` returns nil, but
    /// `getStale(_)` will return it (SWR).
    func restore(key: Key, value: Value, storedAt: Date) {
        storage[key] = Entry(value: value, storedAt: storedAt)
        evictOverflow()
    }

    private func isExpired(_ entry: Entry) -> Bool {
        Date().timeIntervalSince(entry.storedAt) >= ttl
    }

    /// Trims the map back to `maxEntries`. Only runs when the cache is over
    /// the limit, so a stale-but-wanted entry survives as long as there is
    /// space for it. Oldest `storedAt` goes first — with a single TTL that is
    /// the same thing as "expired entries before fresh ones".
    private func evictOverflow() {
        var overflow = storage.count - maxEntries
        guard overflow > 0 else { return }
        let victims = storage
            .map { (key: $0.key, storedAt: $0.value.storedAt) }
            .sorted { $0.storedAt < $1.storedAt }
        for victim in victims {
            guard overflow > 0 else { break }
            storage.removeValue(forKey: victim.key)
            overflow -= 1
        }
    }
}
