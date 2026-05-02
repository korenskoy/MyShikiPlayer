//
//  AppSupportStore.swift
//  MyShikiPlayer
//
//  Generic helper for JSON persistence in Application Support.
//  Unlike DiskBackup (which targets the Caches directory and wraps TTLCache),
//  this helper targets ~/Library/Application Support/MyShikiPlayer/ for data
//  that must survive OS cache eviction.
//

import Foundation

enum AppSupportStore {

  /// Returns <AppSupport>/MyShikiPlayer/<filename>, creating the directory if needed.
  static func fileURL(filename: String) -> URL {
    let base = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first!
    let dir = base.appendingPathComponent("MyShikiPlayer", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(filename)
  }

  /// Decodes JSON from the file. Returns nil if the file does not exist.
  static func loadJSON<T: Decodable>(_ type: T.Type, filename: String) throws -> T? {
    let url = fileURL(filename: filename)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(type, from: data)
  }

  /// Encodes value as JSON and writes it atomically.
  static func saveJSON<T: Encodable>(_ value: T, filename: String) throws {
    let url = fileURL(filename: filename)
    let data = try JSONEncoder().encode(value)
    let tmp = url.appendingPathExtension("tmp")
    try data.write(to: tmp, options: .atomic)
    _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
  }
}
