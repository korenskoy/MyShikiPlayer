//
//  Anime365ServiceTests.swift
//  MyShikiPlayerTests
//

import XCTest
@testable import MyShikiPlayer

// MARK: - Fixtures

private func mockEndpointConfig() -> SubtitleEndpointConfig {
  SubtitleEndpointConfig(host: "https://media.example.com", api: "https://api.example.com")
}

private func makeResponse(_ url: URL, statusCode: Int = 200) -> HTTPURLResponse {
  HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

private func jsonData(_ value: Any) -> Data {
  // swiftlint:disable:next force_try
  try! JSONSerialization.data(withJSONObject: value)
}

// MARK: - Stub endpoint store

@MainActor
private final class StubEndpointStore: SubtitleEndpointStore {
  private let config: SubtitleEndpointConfig

  init(config: SubtitleEndpointConfig) {
    let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("noop.json")
    super.init(session: .shared, cacheURL: tmpURL)
    self.config = config
  }

  override func endpoints() async throws -> SubtitleEndpointConfig {
    config
  }

  override func refresh() async throws -> SubtitleEndpointConfig {
    config
  }
}

// MARK: - Tests

@MainActor
final class Anime365ServiceTests: XCTestCase {

  // MARK: - Helpers

  private func makeService(
    handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
  ) async -> Anime365Service {
    MockURLProtocol.handler = handler
    let session = MockURLSession.make()
    let store = StubEndpointStore(config: mockEndpointConfig())
    return Anime365Service(session: session, endpointStore: store)
  }

  // MARK: - Request URL tests

  func test_seriesListURLContainsMalId() async throws {
    var capturedURL: URL?
    let service = await makeService { request in
      capturedURL = request.url
      let payload: [String: Any] = ["id": 42, "myAnimeListId": 1234, "title": "Test Anime"]
      return (makeResponse(request.url!), jsonData([payload]))
    }

    _ = try? await service.searchSubtitles(shikimoriId: 1234, episode: 1)
    XCTAssertTrue(capturedURL?.absoluteString.contains("myAnimeListId=1234") == true)
  }

  func test_seriesDetailURLContainsFieldsEpisodes() async throws {
    var requestedURLs: [URL] = []
    let seriesData: [String: Any] = ["id": 99, "myAnimeListId": 5]
    let episodesPayload: [String: Any] = [
      "id": 99,
      "episodes": [
        ["id": 10, "isActive": 1, "episodeInt": "1", "episodeType": "regular"]
      ]
    ]

    let service = await makeService { request in
      requestedURLs.append(request.url!)
      if request.url?.absoluteString.contains("/series/") == true
          && request.url?.query?.contains("fields=episodes") == true {
        return (makeResponse(request.url!), jsonData(episodesPayload))
      }
      return (makeResponse(request.url!), jsonData([seriesData]))
    }
    _ = try? await service.searchSubtitles(shikimoriId: 5, episode: 1)
    XCTAssertTrue(requestedURLs.contains { $0.absoluteString.contains("fields=episodes") })
  }

  // MARK: - Header tests

  func test_restRequestsCarryCorrectUserAgent() async throws {
    var capturedUA: String?
    let service = await makeService { request in
      if capturedUA == nil {
        capturedUA = request.value(forHTTPHeaderField: "User-Agent")
      }
      return (makeResponse(request.url!), jsonData([] as [Any]))
    }
    _ = try? await service.searchSubtitles(shikimoriId: 1, episode: 1)
    XCTAssertEqual(capturedUA, Anime365Endpoint.userAgentRestApi)
  }

  func test_restRequestsCarryCorrectCacheControl() async throws {
    var capturedCC: String?
    let service = await makeService { request in
      if capturedCC == nil {
        capturedCC = request.value(forHTTPHeaderField: "Cache-Control")
      }
      return (makeResponse(request.url!), jsonData([] as [Any]))
    }
    _ = try? await service.searchSubtitles(shikimoriId: 1, episode: 1)
    XCTAssertEqual(capturedCC, Anime365Endpoint.cacheControlValue)
  }

  // MARK: - Filter tests

  func test_inactiveEpisodesAreExcluded() async throws {
    let seriesData: [String: Any] = ["id": 1, "myAnimeListId": 10]
    let episodes: [[String: Any]] = [
      ["id": 11, "isActive": 0, "episodeInt": "1", "episodeType": "regular"],
      ["id": 12, "isActive": 1, "episodeInt": "1", "episodeType": "regular"]
    ]
    let seriesDetail: [String: Any] = ["id": 1, "episodes": episodes]
    let episodeDetail: [String: Any] = [
      "id": 12, "isActive": 1, "episodeInt": "1", "episodeType": "regular",
      "translations": [
        ["id": 200, "type": "subru", "typeKind": "sub", "isActive": 1]
      ]
    ]

    let service = await makeService { request in
      let url = request.url!.absoluteString
      if url.contains("/series/1?fields=episodes") {
        return (makeResponse(request.url!), jsonData(seriesDetail))
      } else if url.contains("/episodes/") {
        return (makeResponse(request.url!), jsonData(episodeDetail))
      }
      return (makeResponse(request.url!), jsonData([seriesData]))
    }

    let result = try await service.searchSubtitles(shikimoriId: 10, episode: 1)
    // episode 11 (isActive=0) should be excluded; episode 12 should match
    XCTAssertEqual(result.seriaId, 12)
  }

  func test_previewEpisodesAreExcluded() async throws {
    let seriesData: [String: Any] = ["id": 2, "myAnimeListId": 20]
    let episodes: [[String: Any]] = [
      ["id": 21, "isActive": 1, "episodeInt": "1", "episodeType": "Preview"],
      ["id": 22, "isActive": 1, "episodeInt": "1", "episodeType": "regular"]
    ]
    let seriesDetail: [String: Any] = ["id": 2, "episodes": episodes]
    let episodeDetail: [String: Any] = [
      "id": 22, "isActive": 1, "episodeInt": "1", "episodeType": "regular",
      "translations": []
    ]

    let service = await makeService { request in
      let url = request.url!.absoluteString
      if url.contains("/series/2?fields=episodes") {
        return (makeResponse(request.url!), jsonData(seriesDetail))
      } else if url.contains("/episodes/") {
        return (makeResponse(request.url!), jsonData(episodeDetail))
      }
      return (makeResponse(request.url!), jsonData([seriesData]))
    }

    let result = try await service.searchSubtitles(shikimoriId: 20, episode: 1)
    XCTAssertEqual(result.seriaId, 22)
  }

  func test_nonSubTranslationsAreExcluded() async throws {
    let seriesData: [String: Any] = ["id": 3, "myAnimeListId": 30]
    let seriesDetail: [String: Any] = [
      "id": 3,
      "episodes": [["id": 31, "isActive": 1, "episodeInt": "1", "episodeType": "regular"]]
    ]
    let episodeDetail: [String: Any] = [
      "id": 31, "isActive": 1, "episodeInt": "1", "episodeType": "regular",
      "translations": [
        ["id": 300, "type": "subru", "typeKind": "sub", "isActive": 1],
        ["id": 301, "type": "russound", "typeKind": "voice", "isActive": 1],
        ["id": 302, "type": "suben", "typeKind": "Sub", "isActive": 1]
      ]
    ]

    let service = await makeService { request in
      let url = request.url!.absoluteString
      if url.contains("/series/3?fields=episodes") {
        return (makeResponse(request.url!), jsonData(seriesDetail))
      } else if url.contains("/episodes/") {
        return (makeResponse(request.url!), jsonData(episodeDetail))
      }
      return (makeResponse(request.url!), jsonData([seriesData]))
    }

    let result = try await service.searchSubtitles(shikimoriId: 30, episode: 1)
    // typeKind="voice" should be excluded; both sub rows should be kept
    let ids = result.subtitles.map(\.translationId)
    XCTAssertTrue(ids.contains(300))
    XCTAssertFalse(ids.contains(301))
    XCTAssertTrue(ids.contains(302))
  }

  func test_langFilterSubRu() async throws {
    let seriesData: [String: Any] = ["id": 4, "myAnimeListId": 40]
    let seriesDetail: [String: Any] = [
      "id": 4,
      "episodes": [["id": 41, "isActive": 1, "episodeInt": "1", "episodeType": "regular"]]
    ]
    let episodeDetail: [String: Any] = [
      "id": 41, "isActive": 1, "episodeInt": "1", "episodeType": "regular",
      "translations": [
        ["id": 400, "type": "subru", "typeKind": "sub", "isActive": 1],
        ["id": 401, "type": "suben", "typeKind": "sub", "isActive": 1]
      ]
    ]

    let service = await makeService { request in
      let url = request.url!.absoluteString
      if url.contains("/series/4?fields=episodes") {
        return (makeResponse(request.url!), jsonData(seriesDetail))
      } else if url.contains("/episodes/") {
        return (makeResponse(request.url!), jsonData(episodeDetail))
      }
      return (makeResponse(request.url!), jsonData([seriesData]))
    }

    let result = try await service.searchSubtitles(shikimoriId: 40, episode: 1, lang: .subRu)
    let ids = result.subtitles.map(\.translationId)
    XCTAssertEqual(ids, [400])
  }

  // MARK: - URL building

  func test_assURLShape() {
    let url = Anime365Endpoint.assURL(host: "https://media.example.com", translationId: 42)
    XCTAssertEqual(url?.absoluteString, "https://media.example.com/episodeTranslations/42.ass?willcache")
  }

  func test_vttURLShape() {
    let url = Anime365Endpoint.vttURL(host: "https://media.example.com/", translationId: 7)
    XCTAssertEqual(url?.absoluteString, "https://media.example.com/translations/vtt/7")
  }

  // MARK: - unwrapData (envelope)

  func test_wrappedDataEnvelopeDecodes() throws {
    let json = """
    {"data": [{"id": 1, "myAnimeListId": 5}]}
    """.data(using: .utf8)!
    let envelope = try JSONDecoder().decode(Anime365DataEnvelope<[Anime365Series]>.self, from: json)
    XCTAssertEqual(envelope.value.count, 1)
    XCTAssertEqual(envelope.value[0].id, 1)
  }

  func test_flatArrayDecodes() throws {
    let json = """
    [{"id": 2, "myAnimeListId": 9}]
    """.data(using: .utf8)!
    let envelope = try JSONDecoder().decode(Anime365DataEnvelope<[Anime365Series]>.self, from: json)
    XCTAssertEqual(envelope.value.count, 1)
    XCTAssertEqual(envelope.value[0].myAnimeListId, 9)
  }

  // MARK: - Error propagation

  func test_noSeriesThrows() async {
    let service = await makeService { request in
      (makeResponse(request.url!), jsonData([] as [Any]))
    }
    do {
      _ = try await service.searchSubtitles(shikimoriId: 999, episode: 1)
      XCTFail("Expected error")
    } catch Anime365Error.noSeriesForShikimoriId {
      // expected
    } catch {
      XCTFail("Wrong error: \(error)")
    }
  }

  func test_noEpisodeThrows() async {
    let seriesData: [String: Any] = ["id": 5, "myAnimeListId": 50]
    let seriesDetail: [String: Any] = ["id": 5, "episodes": [] as [[String: Any]]]

    let service = await makeService { request in
      let url = request.url!.absoluteString
      if url.contains("/series/5?fields=episodes") {
        return (makeResponse(request.url!), jsonData(seriesDetail))
      }
      return (makeResponse(request.url!), jsonData([seriesData]))
    }

    do {
      _ = try await service.searchSubtitles(shikimoriId: 50, episode: 1)
      XCTFail("Expected error")
    } catch Anime365Error.noEpisodeFound {
      // expected
    } catch {
      XCTFail("Wrong error type: \(error)")
    }
  }
}
