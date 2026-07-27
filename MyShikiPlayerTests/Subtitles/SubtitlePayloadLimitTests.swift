//
//  SubtitlePayloadLimitTests.swift
//  MyShikiPlayerTests
//

import Foundation
import Testing
@testable import MyShikiPlayer

// MARK: - Helpers

private func respond(_ url: URL, data: Data, contentLength: Int? = nil) -> (HTTPURLResponse, Data) {
  var headers: [String: String] = [:]
  if let contentLength { headers["Content-Length"] = String(contentLength) }
  let response = HTTPURLResponse(
    url: url,
    statusCode: 200,
    httpVersion: "HTTP/1.1",
    headerFields: headers
  )!
  return (response, data)
}

/// Runs `body` and returns the error it threw, or nil when it unexpectedly succeeded.
private func capturedFailure(_ body: () async throws -> Void) async -> Error? {
  do {
    try await body()
    return nil
  } catch {
    return error
  }
}

/// Unwraps the cap that `BoundedDataLoader` tripped on, from inside a loader's
/// `downloadFailed` case.
private func oversizeLimit(_ error: Error) -> Int? {
  let underlying: Error
  switch error {
  case let assError as ASSLoaderError:
    guard case .downloadFailed(let inner) = assError else { return nil }
    underlying = inner
  case let vttError as VTTLoaderError:
    guard case .downloadFailed(let inner) = vttError else { return nil }
    underlying = inner
  default:
    return nil
  }
  guard let bounded = underlying as? BoundedResponseError else { return nil }
  guard case .tooLarge(let limit) = bounded else { return nil }
  return limit
}

// MARK: - Tests

// Each test owns its session, so the stubs are hermetic and the suite can run in parallel.
@Suite("Subtitle payload limits")
struct SubtitlePayloadLimitTests {

  private static let assURL = URL(string: "https://media.example.com/episodeTranslations/1.ass")!
  private static let vttURL = URL(string: "https://media.example.com/translations/vtt/1")!

  // MARK: - ASS

  @Test("An ASS body within the cap is returned untouched")
  func assWithinLimitPasses() async throws {
    let body = Data("[Script Info]\nTitle: ok\n".utf8)
    let session = MockURLSession.make { request in respond(request.url!, data: body) }

    let loader = ASSLoader(session: session)
    let data = try await loader.loadRawBytes(Self.assURL)
    #expect(data == body)
  }

  @Test("An ASS body advertising more than the cap is rejected before it is read")
  func assRejectsOversizeContentLength() async {
    let body = Data(repeating: 0x41, count: 16)
    let advertised = ResponseSizeLimit.subtitle + 1
    let session = MockURLSession.make { request in
      respond(request.url!, data: body, contentLength: advertised)
    }

    let loader = ASSLoader(session: session)
    let failure = await capturedFailure { _ = try await loader.loadRawBytes(Self.assURL) }
    #expect(failure.flatMap(oversizeLimit) == ResponseSizeLimit.subtitle)
  }

  @Test("An ASS body that outgrows the cap mid-stream is rejected")
  func assRejectsOversizeBody() async {
    // No Content-Length header: the running total is the only thing enforcing the cap.
    let body = Data(repeating: 0x41, count: ResponseSizeLimit.subtitle + 1)
    let session = MockURLSession.make { request in respond(request.url!, data: body) }

    let loader = ASSLoader(session: session)
    let failure = await capturedFailure { _ = try await loader.loadRawBytes(Self.assURL) }
    #expect(failure.flatMap(oversizeLimit) == ResponseSizeLimit.subtitle)
  }

  // MARK: - VTT

  @Test("A VTT body within the cap still parses")
  func vttWithinLimitPasses() async throws {
    let body = Data("WEBVTT\n\n1\n00:00:01.000 --> 00:00:03.000\nHello.\n".utf8)
    let session = MockURLSession.make { request in respond(request.url!, data: body) }

    let loader = VTTLoader(session: session)
    let cues = try await loader.load(Self.vttURL)
    #expect(cues.count == 1)
  }

  @Test("A VTT body advertising more than the cap is rejected before it is read")
  func vttRejectsOversizeContentLength() async {
    let body = Data("WEBVTT\n".utf8)
    let advertised = ResponseSizeLimit.subtitle + 1
    let session = MockURLSession.make { request in
      respond(request.url!, data: body, contentLength: advertised)
    }

    let loader = VTTLoader(session: session)
    let failure = await capturedFailure { _ = try await loader.load(Self.vttURL) }
    #expect(failure.flatMap(oversizeLimit) == ResponseSizeLimit.subtitle)
  }
}
