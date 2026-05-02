//
//  SubtitleEndpointStoreTests.swift
//  MyShikiPlayerTests
//

import XCTest
@testable import MyShikiPlayer

// MARK: - Helpers

private func tempCacheURL() -> URL {
  URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent(UUID().uuidString)
    .appendingPathComponent("subtitle-endpoints.json")
}

private func makeResponse(_ url: URL, statusCode: Int = 200) -> HTTPURLResponse {
  HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}

private let placeholderConfig = SubtitleEndpointConfig(
  host: "https://test-host.example.com",
  api: "https://test-api.example.com"
)

// MARK: - Tests

@MainActor
final class SubtitleEndpointStoreTests: XCTestCase {

  // MARK: - Cold start with no file triggers network

  func test_coldStartWithNoFileFetchesNetwork() async throws {
    var networkCallCount = 0
    let cacheURL = tempCacheURL()
    try? FileManager.default.removeItem(at: cacheURL)

    MockURLProtocol.handler = { request in
      networkCallCount += 1
      throw URLError(.notConnectedToInternet)
    }
    let session = MockURLSession.make()
    let store = SubtitleEndpointStore(session: session, cacheURL: cacheURL)

    do {
      _ = try await store.endpoints()
    } catch {
      // Expected: no cache + network fail → throws
    }
    XCTAssertEqual(networkCallCount, 1)
  }

  // MARK: - Subsequent calls with cached file skip network

  func test_cachedFileSkipsNetwork() async throws {
    var networkCallCount = 0
    let cacheURL = tempCacheURL()

    let config = placeholderConfig
    let dir = cacheURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(config)
    try data.write(to: cacheURL)

    MockURLProtocol.handler = { _ in
      networkCallCount += 1
      throw URLError(.notConnectedToInternet)
    }
    let session = MockURLSession.make()
    let store = SubtitleEndpointStore(session: session, cacheURL: cacheURL)

    let result = try await store.endpoints()
    XCTAssertEqual(result, config)
    XCTAssertEqual(networkCallCount, 0)

    _ = try await store.endpoints()
    XCTAssertEqual(networkCallCount, 0)
  }

  // MARK: - Explicit refresh triggers exactly one network call

  func test_explicitRefreshTriggersOneNetworkCall() async throws {
    var networkCallCount = 0
    let cacheURL = tempCacheURL()
    try? FileManager.default.removeItem(at: cacheURL)

    MockURLProtocol.handler = { _ in
      networkCallCount += 1
      throw URLError(.notConnectedToInternet)
    }
    let session = MockURLSession.make()
    let store = SubtitleEndpointStore(session: session, cacheURL: cacheURL)

    do { try await store.refresh() } catch {}
    XCTAssertEqual(networkCallCount, 1)

    do { try await store.refresh() } catch {}
    XCTAssertEqual(networkCallCount, 2)
  }

  // MARK: - Failed refresh with stale cache returns stale

  func test_failedRefreshWithStaleCacheReturnsStale() async throws {
    let cacheURL = tempCacheURL()
    let stale = placeholderConfig

    let dir = cacheURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try JSONEncoder().encode(stale).write(to: cacheURL)

    MockURLProtocol.handler = { _ in
      throw URLError(.notConnectedToInternet)
    }
    let session = MockURLSession.make()
    let store = SubtitleEndpointStore(session: session, cacheURL: cacheURL)

    let result1 = try await store.endpoints()
    XCTAssertEqual(result1, stale)

    // Explicit refresh fails → should return stale (not throw)
    let result2 = try await store.refresh()
    XCTAssertEqual(result2, stale)
  }

  // MARK: - Failed refresh with no cache throws

  func test_failedRefreshWithNoCacheThrows() async throws {
    let cacheURL = tempCacheURL()
    try? FileManager.default.removeItem(at: cacheURL)

    MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
    let session = MockURLSession.make()
    let store = SubtitleEndpointStore(session: session, cacheURL: cacheURL)

    do {
      _ = try await store.refresh()
      XCTFail("Expected error")
    } catch Anime365Error.endpointConfigUnavailable {
      // expected
    } catch {
      XCTFail("Wrong error type: \(error)")
    }
  }
}
