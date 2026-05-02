//
//  SubtitleEndpointStore.swift
//  MyShikiPlayer
//

import Foundation

/// Persistent cache for subtitle endpoint configuration.
///
/// Reads `subtitle-endpoints.json` from Application Support on first access.
/// A network fetch happens only when no cached file exists, or when `refresh()` is called
/// explicitly (typically after a request failure in Anime365Service).
/// If refresh fails and stale data is cached, the stale value is returned and the
/// error is propagated to the caller for non-fatal reporting.
@MainActor
class SubtitleEndpointStore {

  static let shared = SubtitleEndpointStore()

  private var cached: SubtitleEndpointConfig?
  private let cacheURL: URL
  private let httpClient: LoggedHTTPClient

  init(session: URLSession = .shared, cacheURL: URL? = nil) {
    self.httpClient = LoggedHTTPClient(session: session)
    self.cacheURL = cacheURL ?? AppSupportStore.fileURL(filename: "subtitle-endpoints.json")
  }

  // MARK: - Public API

  /// Returns the current endpoint config, loading from disk if needed.
  /// Triggers a network fetch on first call when no file exists.
  func endpoints() async throws -> SubtitleEndpointConfig {
    if let cached { return cached }

    if let fromDisk = loadFromDisk() {
      cached = fromDisk
      return fromDisk
    }

    return try await refresh()
  }

  /// Fetches a fresh config from the network and persists it.
  /// If the network call fails and stale data is cached, the stale value is returned.
  @discardableResult
  func refresh() async throws -> SubtitleEndpointConfig {
    do {
      let fresh = try await fetchFromNetwork()
      cached = fresh
      saveToDisk(fresh)
      return fresh
    } catch {
      // Stale cache is better than nothing — keep using it.
      if let stale = cached { return stale }
      throw Anime365Error.endpointConfigUnavailable
    }
  }

  // MARK: - Disk

  private func loadFromDisk() -> SubtitleEndpointConfig? {
    guard FileManager.default.fileExists(atPath: cacheURL.path),
          let data = try? Data(contentsOf: cacheURL)
    else { return nil }
    return try? JSONDecoder().decode(SubtitleEndpointConfig.self, from: data)
  }

  private func saveToDisk(_ config: SubtitleEndpointConfig) {
    guard let data = try? JSONEncoder().encode(config) else { return }
    let dir = cacheURL.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let tmp = cacheURL.appendingPathExtension("tmp")
    do {
      try data.write(to: tmp, options: .atomic)
      _ = try? FileManager.default.replaceItemAt(cacheURL, withItemAt: tmp)
    } catch {
      try? FileManager.default.removeItem(at: tmp)
    }
  }

  // MARK: - Network

  private func fetchFromNetwork() async throws -> SubtitleEndpointConfig {
    guard let urlString = SubtitleConfigCipher.decryptEndpointUrl(),
          let innerKey = SubtitleConfigCipher.decryptInnerXorKey(),
          let url = URL(string: urlString)
    else {
      throw Anime365Error.endpointConfigUnavailable
    }

    var request = URLRequest(url: url, timeoutInterval: 10)
    request.httpMethod = "GET"
    Anime365Endpoint.endpointFetchHeaders().forEach { request.setValue($1, forHTTPHeaderField: $0) }

    let data: Data
    let http: HTTPURLResponse
    do {
      (data, http) = try await httpClient.data(for: request)
    } catch {
      throw Anime365Error.networkError(underlying: error)
    }

    if !(200..<300).contains(http.statusCode) {
      throw Anime365Error.networkError(underlying: URLError(.badServerResponse))
    }

    let raw: SubtitleEndpointConfigRaw
    do {
      raw = try JSONDecoder().decode(SubtitleEndpointConfigRaw.self, from: data)
    } catch {
      throw Anime365Error.decodeError(underlying: error)
    }

    guard
      let host = SubtitleConfigCipher.decryptConfigField(raw.host, innerKey: innerKey),
      let api = SubtitleConfigCipher.decryptConfigField(raw.api, innerKey: innerKey)
    else {
      throw Anime365Error.decodeError(underlying: SubtitleCipherError.decryptionFailed)
    }

    return SubtitleEndpointConfig(
      host: host.trimmingCharacters(in: CharacterSet(charactersIn: "/")),
      api: api.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    )
  }

}

// MARK: - Internal error

private enum SubtitleCipherError: Error {
  case decryptionFailed
}
