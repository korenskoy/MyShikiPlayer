//
//  Anime365Service.swift
//  MyShikiPlayer
//

import Foundation

// MARK: - Error type

enum Anime365Error: Error, LocalizedError, Sendable {
  case noSeriesForShikimoriId
  case noEpisodeFound
  case networkError(underlying: Error)
  case decodeError(underlying: Error)
  case endpointConfigUnavailable

  var errorDescription: String? {
    switch self {
    case .noSeriesForShikimoriId:
      return "Аниме не найдено в источнике субтитров."
    case .noEpisodeFound:
      return "Эпизод не найден в источнике субтитров."
    case .networkError(let err):
      return "Ошибка сети при загрузке субтитров: \(err.localizedDescription)"
    case .decodeError(let err):
      return "Не удалось разобрать ответ источника субтитров: \(err.localizedDescription)"
    case .endpointConfigUnavailable:
      return "Конфигурация источника субтитров недоступна."
    }
  }
}

// MARK: - Throttler

private actor Anime365Throttler {
  private var activeCount = 0
  private let maxConcurrent: Int
  private var waiters: [CheckedContinuation<Void, Never>] = []

  init(maxConcurrent: Int = 5) {
    self.maxConcurrent = maxConcurrent
  }

  func acquire() async {
    if activeCount < maxConcurrent {
      activeCount += 1
    } else {
      await withCheckedContinuation { continuation in
        waiters.append(continuation)
      }
      activeCount += 1
    }
  }

  func release() {
    activeCount -= 1
    if !waiters.isEmpty {
      let waiter = waiters.removeFirst()
      waiter.resume()
    }
  }
}

// MARK: - Service

/// Runs the full subtitle-lookup pipeline: series → episode → translations.
/// Mirrors the TypeScript reference implementation in docs/subs/subs.ts.
@MainActor
final class Anime365Service {

  private let httpClient: LoggedHTTPClient
  private let endpointStore: SubtitleEndpointStore
  private let throttler = Anime365Throttler()

  init(session: URLSession = .shared, endpointStore: SubtitleEndpointStore? = nil) {
    self.httpClient = LoggedHTTPClient(session: session)
    self.endpointStore = endpointStore ?? SubtitleEndpointStore.shared
  }

  // MARK: - Public

  /// Searches for subtitle candidates for a given Shikimori anime id and episode number.
  func searchSubtitles(
    shikimoriId: Int,
    episode: Int,
    lang: Anime365LangFilter = .all,
    checkAss: Bool = false
  ) async throws -> SubtitleSearchResult {
    let config = try await fetchEndpoints()

    // 1. Find the series by MAL id (Shikimori uses the same integer id as MAL)
    guard let seriesURL = Anime365Endpoint.seriesListURL(api: config.api, myAnimeListId: shikimoriId) else {
      throw Anime365Error.networkError(underlying: URLError(.badURL))
    }
    let seriesList = try await fetchJSON([Anime365Series].self, from: seriesURL, config: config)
    guard let series = seriesList.first else {
      throw Anime365Error.noSeriesForShikimoriId
    }

    // 2. Fetch episodes for this series
    guard let seriesDetailURL = Anime365Endpoint.seriesDetailURL(api: config.api, seriesId: series.id) else {
      throw Anime365Error.networkError(underlying: URLError(.badURL))
    }

    struct SeriesWithEpisodes: Decodable {
      let episodes: [Anime365EpisodeSummary]?
    }
    let seriesDetail = try await fetchJSON(SeriesWithEpisodes.self, from: seriesDetailURL, config: config)
    let episodes = seriesDetail.episodes ?? []

    // 3. Find the matching episode
    let seria = episodes
      .filter { $0.isActive == 1 && $0.episodeType.lowercased() != "preview" }
      .first { episodeMatches($0.episodeInt, requested: episode) }
    guard let seria else {
      throw Anime365Error.noEpisodeFound
    }

    // 4. Fetch episode detail (includes translations)
    guard let episodeURL = Anime365Endpoint.episodeDetailURL(api: config.api, seriaId: seria.id) else {
      throw Anime365Error.networkError(underlying: URLError(.badURL))
    }
    let episodeDetail = try await fetchJSON(Anime365EpisodeDetail.self, from: episodeURL, config: config)

    // 5. Filter translations
    let filtered = episodeDetail.translations.filter { translation in
      guard translation.isActive == 1 else { return false }
      guard translation.typeKind.lowercased() == "sub" else { return false }
      if lang == .all { return true }
      return translation.type.lowercased() == lang.rawValue.lowercased()
    }

    // 6. Build candidates (optionally checking ASS availability concurrently)
    let buildable = filtered.compactMap { translation -> (Anime365Translation, URL, URL)? in
      guard
        let assURL = Anime365Endpoint.assURL(host: config.host, translationId: translation.id),
        let vttURL = Anime365Endpoint.vttURL(host: config.host, translationId: translation.id)
      else { return nil }
      return (translation, assURL, vttURL)
    }

    let availability: [Int: Bool]
    if checkAss {
      availability = await withTaskGroup(of: (Int, Bool).self) { group in
        for (translation, assURL, _) in buildable {
          let id = translation.id
          group.addTask { (id, await self.checkAssAvailable(assURL)) }
        }
        var result: [Int: Bool] = [:]
        for await (id, ok) in group { result[id] = ok }
        return result
      }
    } else {
      availability = [:]
    }

    let candidates: [SubtitleCandidate] = buildable.compactMap { (translation, assURL, vttURL) in
      if checkAss, availability[translation.id] != true { return nil }
      return SubtitleCandidate(
        translationId: translation.id,
        type: translation.type,
        typeKind: translation.typeKind,
        title: translation.title,
        authorsSummary: translation.authorsSummary,
        assURL: assURL,
        vttURL: vttURL
      )
    }

    return SubtitleSearchResult(
      shikimoriId: shikimoriId,
      requestedEpisode: episode,
      seriesId: series.id,
      seriaId: seria.id,
      title: series.title,
      subtitles: candidates
    )
  }

  // MARK: - Private helpers

  private func fetchEndpoints() async throws -> SubtitleEndpointConfig {
    try await endpointStore.endpoints()
  }

  private func fetchJSON<T: Decodable>(
    _ type: T.Type,
    from url: URL,
    config: SubtitleEndpointConfig
  ) async throws -> T {
    await throttler.acquire()
    defer { Task { await throttler.release() } }

    var request = URLRequest(url: url, timeoutInterval: 10)
    request.httpMethod = "GET"
    Anime365Endpoint.restAPIHeaders().forEach { request.setValue($1, forHTTPHeaderField: $0) }

    let data: Data
    let http: HTTPURLResponse
    do {
      (data, http) = try await httpClient.data(for: request)
    } catch {
      // Trigger endpoint refresh on network error
      try? await endpointStore.refresh()
      throw Anime365Error.networkError(underlying: error)
    }

    if !(200..<300).contains(http.statusCode) {
      // Refresh endpoints — the failure might be due to a stale config
      try? await endpointStore.refresh()
      throw Anime365Error.networkError(underlying: URLError(.badServerResponse))
    }

    let envelope: Anime365DataEnvelope<T>
    do {
      envelope = try JSONDecoder().decode(Anime365DataEnvelope<T>.self, from: data)
    } catch {
      throw Anime365Error.decodeError(underlying: error)
    }
    return envelope.value
  }

  private func checkAssAvailable(_ url: URL) async -> Bool {
    var request = URLRequest(url: url, timeoutInterval: 10)
    request.httpMethod = "HEAD"
    Anime365Endpoint.endpointFetchHeaders().forEach { request.setValue($1, forHTTPHeaderField: $0) }
    do {
      let (_, http) = try await httpClient.data(for: request)
      return (200..<300).contains(http.statusCode)
    } catch {
      return false
    }
  }
}

// MARK: - Helpers

private func episodeMatches(_ episodeInt: String, requested: Int) -> Bool {
  guard let parsed = Double(episodeInt), parsed.isFinite else { return false }
  return parsed == Double(requested)
}
