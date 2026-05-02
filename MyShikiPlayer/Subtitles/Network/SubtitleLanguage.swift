//
//  SubtitleLanguage.swift
//  MyShikiPlayer
//

import Foundation

// MARK: - SubtitleLanguage

/// Typed representation of a subtitle track's language parsed from the Anime365 `type` field.
enum SubtitleLanguage: Sendable, Hashable {
  case ru
  case en
  case uk
  case ja
  case de
  case fr
  case es
  case zh
  case ko
  case other(String)

  // MARK: - Parsing

  /// Parses the raw `type` field from Anime365 ("subRu", "subEn", "subUk", …).
  /// Returns `.other(raw)` for unknown or non-`sub*` codes; returns nil only for empty input.
  static func parse(apiType raw: String) -> SubtitleLanguage? {
    guard !raw.isEmpty else { return nil }
    switch raw.lowercased() {
    case "subru": return .ru
    case "suben": return .en
    case "subuk": return .uk
    case "subja": return .ja
    case "subde": return .de
    case "subfr": return .fr
    case "subes": return .es
    case "subzh": return .zh
    case "subko": return .ko
    default:      return .other(raw)
    }
  }

  // MARK: - API token

  /// Lowercase API filter token used by Anime365 search ("subru", "suben", …).
  var apiToken: String {
    switch self {
    case .ru:          return "subru"
    case .en:          return "suben"
    case .uk:          return "subuk"
    case .ja:          return "subja"
    case .de:          return "subde"
    case .fr:          return "subfr"
    case .es:          return "subes"
    case .zh:          return "subzh"
    case .ko:          return "subko"
    case .other(let s): return s.lowercased()
    }
  }

  // MARK: - Display

  /// Russian-localized group header (uppercase), used in the track picker.
  var groupTitle: String {
    switch self {
    case .ru:          return "РУССКИЕ"
    case .en:          return "АНГЛИЙСКИЕ"
    case .uk:          return "УКРАИНСКИЕ"
    case .ja:          return "ЯПОНСКИЕ"
    case .de:          return "НЕМЕЦКИЕ"
    case .fr:          return "ФРАНЦУЗСКИЕ"
    case .es:          return "ИСПАНСКИЕ"
    case .zh:          return "КИТАЙСКИЕ"
    case .ko:          return "КОРЕЙСКИЕ"
    case .other(let s): return s.uppercased()
    }
  }

  /// Full sentence label used as the studio name when `authorsSummary` is absent.
  var fallbackLabel: String {
    switch self {
    case .ru:          return "Русские субтитры"
    case .en:          return "English subtitles"
    case .uk:          return "Українські субтитри"
    case .ja:          return "日本語字幕"
    case .de:          return "Deutsche Untertitel"
    case .fr:          return "Sous-titres français"
    case .es:          return "Subtítulos en español"
    case .zh:          return "中文字幕"
    case .ko:          return "한국어 자막"
    case .other(let s): return s
    }
  }
}
