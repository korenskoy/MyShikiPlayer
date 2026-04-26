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

import Foundation

enum DiskBackup {
    private struct PersistedEntry<K: Codable, V: Codable>: Codable {
        let key: K
        let value: V
        let storedAt: Date
    }

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

    /// Serializes all TTLCache entries to JSON and writes them to disk
    /// atomically. Errors are silently ignored (cache is non-critical data).
    @MainActor
    static func save<K: Codable & Hashable, V: Codable>(
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
    static func remove(filename: String) {
        guard let url = fileURL(filename: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
