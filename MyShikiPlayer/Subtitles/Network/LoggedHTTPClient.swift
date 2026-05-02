//
//  LoggedHTTPClient.swift
//  MyShikiPlayer
//

import Foundation

/// Wraps URLSession + NetworkLogStore so every subtitle-feature request
/// is timed and logged uniformly.
struct LoggedHTTPClient: Sendable {
  let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  /// Performs the request, returns (data, response). Logs on success and on transport error.
  /// Caller still inspects the HTTPURLResponse status code for non-2xx handling.
  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let startedAt = Date()
    let method = request.httpMethod ?? "GET"
    let url = request.url

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      let duration = Date().timeIntervalSince(startedAt)
      let desc = error.localizedDescription
      Task { @MainActor in
        NetworkLogStore.shared.log(
          method: method,
          url: url,
          statusCode: nil,
          duration: duration,
          responseBytes: nil,
          responsePreview: nil,
          errorDescription: desc
        )
      }
      throw error
    }

    let http = response as? HTTPURLResponse
    let duration = Date().timeIntervalSince(startedAt)
    let byteCount = data.count
    let statusCode = http?.statusCode
    Task { @MainActor in
      NetworkLogStore.shared.log(
        method: method,
        url: url,
        statusCode: statusCode,
        duration: duration,
        responseBytes: byteCount,
        responsePreview: nil,
        errorDescription: nil
      )
    }

    guard let http else {
      throw URLError(.badServerResponse)
    }
    return (data, http)
  }
}
