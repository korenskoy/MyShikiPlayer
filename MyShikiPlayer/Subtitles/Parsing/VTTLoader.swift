//
//  VTTLoader.swift
//  MyShikiPlayer
//

import Foundation
import SwiftSubtitles

enum VTTLoaderError: Error, LocalizedError {
  case invalidEncoding
  case downloadFailed(underlying: Error)
  case parseFailed(underlying: Error)

  var errorDescription: String? {
    switch self {
    case .invalidEncoding:
      return "Не удалось декодировать файл субтитров: неподдерживаемая кодировка."
    case .downloadFailed(let err):
      return "Ошибка загрузки субтитров: \(err.localizedDescription)"
    case .parseFailed(let err):
      return "Не удалось разобрать VTT-файл субтитров: \(err.localizedDescription)"
    }
  }
}

struct VTTLoader: Sendable {
  private let httpClient: LoggedHTTPClient

  init(session: URLSession = .shared) {
    self.httpClient = LoggedHTTPClient(session: session)
  }

  func load(_ url: URL) async throws -> [SubtitleCue] {
    var request = URLRequest(url: url, timeoutInterval: 10)
    request.httpMethod = "GET"
    Anime365Endpoint.endpointFetchHeaders().forEach { request.setValue($1, forHTTPHeaderField: $0) }

    let data: Data
    do {
      (data, _) = try await httpClient.data(for: request)
    } catch {
      throw VTTLoaderError.downloadFailed(underlying: error)
    }

    // Strip UTF-8 BOM if present, then normalise CRLF.
    let rawBytes = data.stripUTF8BOM()
    guard var content = String(bytes: rawBytes, encoding: .utf8) else {
      throw VTTLoaderError.invalidEncoding
    }
    content = content.replacingOccurrences(of: "\r\n", with: "\n")

    let subtitles: Subtitles
    do {
      subtitles = try Subtitles(content: content, expectedExtension: "vtt")
    } catch {
      throw VTTLoaderError.parseFailed(underlying: error)
    }

    return subtitles.cues.enumerated().map { index, cue in
      SubtitleCue(
        id: index,
        startTime: cue.startTimeInSeconds,
        endTime: cue.endTimeInSeconds,
        text: cue.text
      )
    }
  }
}

// MARK: - Data helpers

private extension Data {
  func stripUTF8BOM() -> Data {
    let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
    guard count >= bom.count else { return self }
    if self.prefix(bom.count).elementsEqual(bom) {
      return dropFirst(bom.count)
    }
    return self
  }
}
