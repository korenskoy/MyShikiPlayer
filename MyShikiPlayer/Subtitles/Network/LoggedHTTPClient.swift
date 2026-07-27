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

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      log(request, startedAt: startedAt, error: error)
      throw error
    }

    let http = response as? HTTPURLResponse
    log(request, startedAt: startedAt, statusCode: http?.statusCode, byteCount: data.count)

    guard let http else {
      throw URLError(.badServerResponse)
    }
    return (data, http)
  }

  /// Same contract as `data(for:)`, but refuses to buffer more than `byteLimit` bytes.
  ///
  /// The ceiling itself is enforced by `boundedData(for:limit:)`, which is the app-wide
  /// primitive for downloads from hosts we do not control; this wrapper exists only to keep
  /// subtitle traffic in the network log like every other request here. Oversized responses
  /// surface as `BoundedResponseError.tooLarge`.
  func data(for request: URLRequest, byteLimit: Int) async throws -> (Data, HTTPURLResponse) {
    let startedAt = Date()

    do {
      let (data, response) = try await session.boundedData(for: request, limit: byteLimit)
      guard let http = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }
      log(request, startedAt: startedAt, statusCode: http.statusCode, byteCount: data.count)
      return (data, http)
    } catch {
      log(request, startedAt: startedAt, error: error)
      throw error
    }
  }

  // MARK: - Logging

  private func log(
    _ request: URLRequest,
    startedAt: Date,
    statusCode: Int? = nil,
    byteCount: Int? = nil,
    error: Error? = nil
  ) {
    let duration = Date().timeIntervalSince(startedAt)
    let method = request.httpMethod ?? "GET"
    let url = request.url
    let errorDescription = error?.localizedDescription
    Task { @MainActor in
      NetworkLogStore.shared.log(
        method: method,
        url: url,
        statusCode: statusCode,
        duration: duration,
        responseBytes: byteCount,
        responsePreview: nil,
        errorDescription: errorDescription
      )
    }
  }
}
