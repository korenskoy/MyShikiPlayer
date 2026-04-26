//
//  TTLCache.swift
//  MyShikiPlayer
//
//  In-memory key→value cache with TTL. Supports stale-while-revalidate:
//  expired values are NOT removed automatically — they are read via
//  `getStale(_:)`. Regular `get(_:)` returns only fresh values.
//

import Foundation

@MainActor
final class TTLCache<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let storedAt: Date
    }

    let ttl: TimeInterval
    private var storage: [Key: Entry] = [:]

    init(ttl: TimeInterval) {
        self.ttl = ttl
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
    }

    func invalidate(_ key: Key) {
        storage.removeValue(forKey: key)
    }

    func invalidateAll() {
        storage.removeAll()
    }

    var isEmpty: Bool { storage.isEmpty }

    /// Snapshot of all entries with their timestamps — for disk serialization.
    var allEntries: [(key: Key, value: Value, storedAt: Date)] {
        storage.map { (key: $0.key, value: $0.value.value, storedAt: $0.value.storedAt) }
    }

    /// Restore an entry preserving its original timestamp — for loading from
    /// disk. If the entry is already past TTL, `get(_)` returns nil, but
    /// `getStale(_)` will return it (SWR).
    func restore(key: Key, value: Value, storedAt: Date) {
        storage[key] = Entry(value: value, storedAt: storedAt)
    }

    private func isExpired(_ entry: Entry) -> Bool {
        Date().timeIntervalSince(entry.storedAt) >= ttl
    }
}
