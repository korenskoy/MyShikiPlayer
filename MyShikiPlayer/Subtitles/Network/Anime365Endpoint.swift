//
//  Anime365Endpoint.swift
//  MyShikiPlayer
//

import Foundation

/// HTTP header constants and URL builders for Anime365 and endpoint-config requests.
enum Anime365Endpoint {

  // MARK: - Header constants

  static let userAgentRestApi = "Anime365Api Library"
  static let userAgentEndpointFetch =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36"
  static let cacheControlValue = "public, max-age=14400"

  // MARK: - Request builders

  /// Headers for Anime365 REST API requests (/series, /episodes).
  static func restAPIHeaders() -> [String: String] {
    [
      "User-Agent": userAgentRestApi,
      "Cache-Control": cacheControlValue
    ]
  }

  /// Headers for endpoint-config fetch and HEAD checks on ASS URLs.
  static func endpointFetchHeaders() -> [String: String] {
    [
      "User-Agent": userAgentEndpointFetch,
      "Cache-Control": cacheControlValue
    ]
  }

  // MARK: - URL builders

  /// Series list URL filtered by MAL id.
  static func seriesListURL(api: String, myAnimeListId: Int) -> URL? {
    let base = api.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let encoded = String(myAnimeListId)
    return URL(string: "\(base)/series/?myAnimeListId=\(encoded)")
  }

  /// Series detail URL with episodes field.
  static func seriesDetailURL(api: String, seriesId: Int) -> URL? {
    let base = api.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return URL(string: "\(base)/series/\(seriesId)?fields=episodes")
  }

  /// Episode detail URL (includes translations array).
  static func episodeDetailURL(api: String, seriaId: Int) -> URL? {
    let base = api.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return URL(string: "\(base)/episodes/\(seriaId)")
  }

  /// ASS subtitle URL.
  ///
  /// `/episodeTranslations/{id}.ass` only serves uploads that were ASS to begin with and
  /// 404s for everything else; this path converts on the server and covers every track.
  static func assURL(host: String, translationId: Int) -> URL? {
    let base = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return URL(string: "\(base)/translations/ass/\(translationId)")
  }

  /// VTT subtitle stream URL.
  static func vttURL(host: String, translationId: Int) -> URL? {
    let base = host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return URL(string: "\(base)/translations/vtt/\(translationId)")
  }
}
