//
//  ASSLoader.swift
//  MyShikiPlayer
//

import Foundation

enum ASSLoaderError: Error, LocalizedError {
  case downloadFailed(underlying: Error)

  var errorDescription: String? {
    switch self {
    case .downloadFailed(let err):
      return "Ошибка загрузки ASS-субтитров: \(err.localizedDescription)"
    }
  }
}

struct ASSLoader: Sendable {
  private let httpClient: LoggedHTTPClient

  init(session: URLSession = .shared) {
    self.httpClient = LoggedHTTPClient(session: session)
  }

  func loadRawBytes(_ url: URL) async throws -> Data {
    var request = URLRequest(url: url, timeoutInterval: 10)
    request.httpMethod = "GET"
    Anime365Endpoint.endpointFetchHeaders().forEach { request.setValue($1, forHTTPHeaderField: $0) }

    do {
      let (data, _) = try await httpClient.data(for: request)
      return data
    } catch {
      throw ASSLoaderError.downloadFailed(underlying: error)
    }
  }
}
