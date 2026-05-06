//
//  TaskDeduplicator.swift
//  MyShikiPlayer
//

import Foundation

/// MainActor-only single-flight registry: at most one in-flight `Task`
/// per key. Concurrent callers requesting the same key share the same
/// underlying task and result.
///
/// Replaces the hand-rolled `private var pending: [Key: Task<Value, Error>]`
/// pattern repeated across every repo. Keep the API minimal — repos
/// already own the cache, retry policy and disk backup; this only handles
/// the dedup half.
@MainActor
final class TaskDeduplicator<Key: Hashable, Value: Sendable> {
    private var pending: [Key: Task<Value, Error>] = [:]

    /// Returns the value for `key`, joining an in-flight task if one exists.
    /// Otherwise starts a new task running `work` and registers it under `key`.
    /// The registry entry is released on completion (success or failure) so
    /// the next request after the cache expires triggers a fresh fetch.
    func run(
        for key: Key,
        _ work: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        if let existing = pending[key] {
            return try await existing.value
        }
        let task = Task<Value, Error> { [weak self] in
            defer { self?.pending.removeValue(forKey: key) }
            return try await work()
        }
        pending[key] = task
        return try await task.value
    }

    /// Cancels and forgets the in-flight task for `key`, if any.
    func cancel(for key: Key) {
        pending[key]?.cancel()
        pending.removeValue(forKey: key)
    }

    /// Cancels all in-flight tasks and clears the registry.
    func cancelAll() {
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
    }
}
