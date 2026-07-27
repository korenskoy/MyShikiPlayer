//
//  DiskBackup.swift
//  MyShikiPlayer
//
//  Utility for saving/loading a TTLCache to disk. Lets caches survive cold
//  start: at startup the repo loads saved entries into memory (even expired
//  ones — SWR will serve them), and writes back on mutations.
//
//  Stores JSON at ~/Library/Caches/MyShikiPlayer/<filename> — the OS may
//  evict it under disk pressure, which is expected cache behavior.
//
//  Writes are coalesced: `save` serializes the whole cache, and repos call it
//  once per loaded item, so a browsing session used to cost O(N^2) bytes.
//  Instead of writing immediately, `save` marks the file dirty and a single
//  timer flushes every dirty cache `flushInterval` seconds later. A crash can
//  therefore lose the last few seconds of *cache* state, which is harmless —
//  the affected repos simply refetch. User data (watch progress, watch
//  history) does not go through DiskBackup at all: those stores persist
//  synchronously through their own UserDefaults / JSON paths.
//

import AppKit
import Foundation

enum DiskBackup {
    private struct PersistedEntry<K: Codable, V: Codable>: Codable {
        let key: K
        let value: V
        let storedAt: Date
    }

    /// Debounce window for cache flushes. Short enough that a normal app quit
    /// (which also force-flushes) never loses anything a user would notice.
    static let flushInterval: TimeInterval = 3

    /// filename → "write the current contents of that cache". Re-assigning the
    /// same key drops the earlier closure, which is exactly the coalescing we
    /// want: only the newest cache state ever reaches the disk.
    @MainActor private static var pendingWrites: [String: @MainActor () -> Void] = [:]
    @MainActor private static var flushTask: Task<Void, Never>?
    @MainActor private static var didInstallLifecycleHooks = false

    /// Path to the file in the user-specific caches directory. Creates the
    /// directory if it does not exist yet. Nil if FileManager did not return
    /// the expected path.
    static func fileURL(filename: String) -> URL? {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let base else { return nil }
        let dir = base.appendingPathComponent("MyShikiPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    /// Marks the cache dirty; the actual JSON dump happens on the next flush.
    @MainActor
    static func save<K: Codable & Hashable, V: Codable>(
        cache: TTLCache<K, V>,
        filename: String
    ) {
        installLifecycleHooksIfNeeded()
        pendingWrites[filename] = { writeNow(cache: cache, filename: filename) }
        scheduleFlush()
    }

    /// Writes every dirty cache right now. Called on app termination, on
    /// resign-active, and by `remove` so an invalidation can never be undone
    /// by a queued write.
    @MainActor
    static func flushPending() {
        flushTask?.cancel()
        flushTask = nil
        let writes = pendingWrites
        pendingWrites.removeAll()
        for write in writes.values { write() }
    }

    /// Reads JSON from disk and restores entries into the TTLCache (with
    /// their original storedAt). Returns the number of loaded entries.
    @MainActor
    static func load<K: Codable & Hashable, V: Codable>(
        into cache: TTLCache<K, V>,
        filename: String
    ) -> Int {
        guard let url = fileURL(filename: filename),
              let data = try? Data(contentsOf: url) else { return 0 }
        do {
            let entries = try JSONDecoder().decode([PersistedEntry<K, V>].self, from: data)
            for entry in entries {
                cache.restore(key: entry.key, value: entry.value, storedAt: entry.storedAt)
            }
            return entries.count
        } catch {
            NetworkLogStore.shared.logAppError(
                "disk_backup_load_failed file=\(filename) err=\(error.localizedDescription)"
            )
            return 0
        }
    }

    /// Remove the cache file from disk (called on invalidateAll).
    @MainActor
    static func remove(filename: String) {
        pendingWrites.removeValue(forKey: filename)
        guard let url = fileURL(filename: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    /// Serializes all TTLCache entries to JSON and writes them to disk
    /// atomically. Errors are silently ignored (cache is non-critical data).
    @MainActor
    private static func writeNow<K: Codable & Hashable, V: Codable>(
        cache: TTLCache<K, V>,
        filename: String
    ) {
        guard let url = fileURL(filename: filename) else { return }
        let entries = cache.allEntries.map {
            PersistedEntry(key: $0.key, value: $0.value, storedAt: $0.storedAt)
        }
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: [.atomic])
        } catch {
            NetworkLogStore.shared.logAppError(
                "disk_backup_save_failed file=\(filename) err=\(error.localizedDescription)"
            )
        }
    }

    @MainActor
    private static func scheduleFlush() {
        // ponytail: one shared timer for every file instead of per-file
        // debouncing — repos write in bursts, so the extra bookkeeping buys
        // nothing.
        guard flushTask == nil else { return }
        flushTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(flushInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            flushPending()
        }
    }

    @MainActor
    private static func installLifecycleHooksIfNeeded() {
        guard !didInstallLifecycleHooks else { return }
        didInstallLifecycleHooks = true
        // ponytail: no unsubscription — DiskBackup is a process-lifetime enum,
        // so these two observers are registered exactly once and never leak.
        let names: [Notification.Name] = [
            NSApplication.willTerminateNotification,
            NSApplication.didResignActiveNotification
        ]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                // `queue: .main` guarantees the main thread; a `Task` hop would
                // be too late on willTerminate.
                MainActor.assumeIsolated { flushPending() }
            }
        }
    }
}
