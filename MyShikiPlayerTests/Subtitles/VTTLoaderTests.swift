//
//  VTTLoaderTests.swift
//  MyShikiPlayerTests
//

import XCTest
@testable import MyShikiPlayer

@MainActor
final class VTTLoaderTests: XCTestCase {

  private var session: URLSession!
  private var loader: VTTLoader!

  override func setUp() {
    super.setUp()
    session = MockURLSession.make()
    loader = VTTLoader(session: session)
  }

  override func tearDown() {
    MockURLProtocol.handler = nil
    session = nil
    loader = nil
    super.tearDown()
  }

  // MARK: - Parsing

  func testParsesStandardCues() async throws {
    MockURLProtocol.handler = { _ in makeResponse(body: vttStandard) }
    let cues = try await loader.load(URL(string: "https://example.com/subs.vtt")!)
    XCTAssertEqual(cues.count, 3)
  }

  func testParsesTimingCorrectly() async throws {
    MockURLProtocol.handler = { _ in makeResponse(body: vttSingleCue) }
    let cues = try await loader.load(URL(string: "https://example.com/subs.vtt")!)
    XCTAssertEqual(cues.count, 1)
    // 00:01:23.456 → 60 + 23 + 0.456 = 83.456
    XCTAssertEqual(cues[0].startTime, 83.456, accuracy: 0.001)
    // 00:01:25.000 → 85.0
    XCTAssertEqual(cues[0].endTime, 85.0, accuracy: 0.001)
    XCTAssertEqual(cues[0].text, "Hello, world!")
  }

  func testParsesMultilineCue() async throws {
    MockURLProtocol.handler = { _ in makeResponse(body: vttMultiline) }
    let cues = try await loader.load(URL(string: "https://example.com/subs.vtt")!)
    XCTAssertEqual(cues.count, 1)
    XCTAssertTrue(cues[0].text.contains("\n"), "Multiline cue should preserve line break")
  }

  func testHandlesBOM() async throws {
    let bomPrefix = Data([0xEF, 0xBB, 0xBF])
    let payload = bomPrefix + Data(vttSingleCue.utf8)
    MockURLProtocol.handler = { _ in makeResponse(data: payload) }
    let cues = try await loader.load(URL(string: "https://example.com/subs.vtt")!)
    XCTAssertEqual(cues.count, 1)
  }

  func testHandlesCRLF() async throws {
    let crlf = vttSingleCue.replacingOccurrences(of: "\n", with: "\r\n")
    MockURLProtocol.handler = { _ in makeResponse(body: crlf) }
    let cues = try await loader.load(URL(string: "https://example.com/subs.vtt")!)
    XCTAssertEqual(cues.count, 1)
  }

  func testCueIdMatchesPosition() async throws {
    MockURLProtocol.handler = { _ in makeResponse(body: vttStandard) }
    let cues = try await loader.load(URL(string: "https://example.com/subs.vtt")!)
    for (index, cue) in cues.enumerated() {
      XCTAssertEqual(cue.id, index)
    }
  }

  // MARK: - Request headers

  func testSendsCorrectUserAgent() async throws {
    var capturedRequest: URLRequest?
    MockURLProtocol.handler = { req in
      capturedRequest = req
      return makeResponse(body: vttSingleCue)
    }
    _ = try await loader.load(URL(string: "https://example.com/subs.vtt")!)
    XCTAssertEqual(
      capturedRequest?.value(forHTTPHeaderField: "User-Agent"),
      Anime365Endpoint.userAgentEndpointFetch
    )
  }

  func testHitsProvidedURL() async throws {
    let target = URL(string: "https://cdn.example.com/ep1.vtt")!
    var capturedURL: URL?
    MockURLProtocol.handler = { req in
      capturedURL = req.url
      return makeResponse(body: vttSingleCue)
    }
    _ = try await loader.load(target)
    XCTAssertEqual(capturedURL, target)
  }

  // MARK: - Error handling

  func testThrowsOnNetworkError() async {
    MockURLProtocol.handler = { _ in throw URLError(.timedOut) }
    do {
      _ = try await loader.load(URL(string: "https://example.com/subs.vtt")!)
      XCTFail("Expected throw")
    } catch let error as VTTLoaderError {
      guard case .downloadFailed = error else {
        return XCTFail("Expected downloadFailed, got \(error)")
      }
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }
}

// MARK: - VTT fixtures

private let vttStandard = """
WEBVTT

1
00:00:01.000 --> 00:00:03.000
First line.

2
00:00:04.000 --> 00:00:06.000
Second line.

3
00:00:07.000 --> 00:00:09.000
Third line.
"""

private let vttSingleCue = """
WEBVTT

1
00:01:23.456 --> 00:01:25.000
Hello, world!
"""

private let vttMultiline = """
WEBVTT

1
00:00:01.000 --> 00:00:04.000
First line
Second line
"""

// MARK: - Helpers

private func makeResponse(body: String) -> (HTTPURLResponse, Data) {
  makeResponse(data: Data(body.utf8))
}

private func makeResponse(data: Data) -> (HTTPURLResponse, Data) {
  let response = HTTPURLResponse(
    url: URL(string: "https://example.com/subs.vtt")!,
    statusCode: 200,
    httpVersion: nil,
    headerFields: nil
  )!
  return (response, data)
}
