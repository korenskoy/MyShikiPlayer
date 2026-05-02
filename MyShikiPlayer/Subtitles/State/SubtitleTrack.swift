//
//  SubtitleTrack.swift
//  MyShikiPlayer
//

import Foundation

struct SubtitleTrack: Sendable, Hashable, Identifiable {
  let id: Int
  /// Parsed language; falls back to `.other(raw)` for unknown codes.
  let language: SubtitleLanguage
  /// Short studio / author label (e.g. "Crunchyroll", "DEEP [с цензурой]").
  /// Falls back to a localized language label when the source omits authorsSummary.
  let studioName: String
  /// Long display title from the source — kept for tooltips.
  let fullTitle: String?
  let vttURL: URL
  let assURL: URL?

  static func make(from candidate: SubtitleCandidate) -> SubtitleTrack {
    let lang = SubtitleLanguage.parse(apiType: candidate.type) ?? .other(candidate.type)
    let trimmedAuthors = candidate.authorsSummary?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let studio: String = {
      if let trimmedAuthors, !trimmedAuthors.isEmpty {
        return trimmedAuthors
      }
      return lang.fallbackLabel
    }()

    return SubtitleTrack(
      id: candidate.translationId,
      language: lang,
      studioName: studio,
      fullTitle: candidate.title,
      vttURL: candidate.vttURL,
      assURL: candidate.assURL
    )
  }
}
