//
//  SubtitleOffsetStorage.swift
//  MyShikiPlayer
//

import Foundation

/// Persists per-(shikimoriId, translationId) subtitle time offsets with LRU eviction at 200 entries.
/// In-memory dictionaries are populated lazily on first access; subsequent reads are O(1).
/// Writes are write-through (update memory + persist JSON). Access timestamps are updated
/// in memory on read and flushed to disk only when a write occurs.
@MainActor
final class SubtitleOffsetStorage {
  static let shared = SubtitleOffsetStorage()

  private let defaults: UserDefaults
  private let offsetsKey = "subtitlesOffsets"
  private let accessKey = "subtitlesOffsetsAccess"
  private let maxEntries = 200

  // MARK: - In-memory cache

  private var offsetCache: [String: Double]?
  private var accessCache: [String: Double]?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  // MARK: - Public API

  func offset(forShikimoriId shikimoriId: Int, translationId: Int) -> Double {
    let key = storageKey(shikimoriId: shikimoriId, translationId: translationId)
    let map = cachedOffsets()
    let value = map[key] ?? 0
    if map[key] != nil {
      // Update in-memory access time only; flush happens on next write.
      accessCache?[key] = Date().timeIntervalSince1970
      if accessCache == nil {
        var ac = loadAccess()
        ac[key] = Date().timeIntervalSince1970
        accessCache = ac
      }
    }
    return value
  }

  func setOffset(_ value: Double, forShikimoriId shikimoriId: Int, translationId: Int) {
    let key = storageKey(shikimoriId: shikimoriId, translationId: translationId)
    var map = cachedOffsets()
    var access = cachedAccess()

    map[key] = value
    access[key] = Date().timeIntervalSince1970

    if map.count > maxEntries {
      evictLRU(map: &map, access: &access)
    }

    offsetCache = map
    accessCache = access
    saveOffsets(map)
    saveAccess(access)
  }

  func reset(forShikimoriId shikimoriId: Int, translationId: Int) {
    let key = storageKey(shikimoriId: shikimoriId, translationId: translationId)
    var map = cachedOffsets()
    var access = cachedAccess()
    map.removeValue(forKey: key)
    access.removeValue(forKey: key)
    offsetCache = map
    accessCache = access
    saveOffsets(map)
    saveAccess(access)
  }

  // MARK: - Private

  private func storageKey(shikimoriId: Int, translationId: Int) -> String {
    "\(shikimoriId):\(translationId)"
  }

  private func cachedOffsets() -> [String: Double] {
    if let cached = offsetCache { return cached }
    let loaded = loadOffsets()
    offsetCache = loaded
    return loaded
  }

  private func cachedAccess() -> [String: Double] {
    if let cached = accessCache { return cached }
    let loaded = loadAccess()
    accessCache = loaded
    return loaded
  }

  private func evictLRU(map: inout [String: Double], access: inout [String: Double]) {
    guard let oldest = access.min(by: { $0.value < $1.value })?.key else { return }
    map.removeValue(forKey: oldest)
    access.removeValue(forKey: oldest)
  }

  private func loadOffsets() -> [String: Double] {
    guard let data = defaults.data(forKey: offsetsKey),
          let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else {
      return [:]
    }
    return decoded
  }

  private func saveOffsets(_ map: [String: Double]) {
    guard let data = try? JSONEncoder().encode(map) else { return }
    defaults.set(data, forKey: offsetsKey)
  }

  private func loadAccess() -> [String: Double] {
    guard let data = defaults.data(forKey: accessKey),
          let decoded = try? JSONDecoder().decode([String: Double].self, from: data) else {
      return [:]
    }
    return decoded
  }

  private func saveAccess(_ map: [String: Double]) {
    guard let data = try? JSONEncoder().encode(map) else { return }
    defaults.set(data, forKey: accessKey)
  }
}
