//
//  SubtitleLanguageTests.swift
//  MyShikiPlayerTests
//

import XCTest
@testable import MyShikiPlayer

final class SubtitleLanguageTests: XCTestCase {

  // MARK: - parse(apiType:)

  func test_parse_knownCodes() {
    XCTAssertEqual(SubtitleLanguage.parse(apiType: "subRu"), .ru)
    XCTAssertEqual(SubtitleLanguage.parse(apiType: "subEn"), .en)
    XCTAssertEqual(SubtitleLanguage.parse(apiType: "subUk"), .uk)
    XCTAssertEqual(SubtitleLanguage.parse(apiType: "subJa"), .ja)
    XCTAssertEqual(SubtitleLanguage.parse(apiType: "subDe"), .de)
    XCTAssertEqual(SubtitleLanguage.parse(apiType: "subFr"), .fr)
    XCTAssertEqual(SubtitleLanguage.parse(apiType: "subEs"), .es)
    XCTAssertEqual(SubtitleLanguage.parse(apiType: "subZh"), .zh)
    XCTAssertEqual(SubtitleLanguage.parse(apiType: "subKo"), .ko)
  }

  func test_parse_caseInsensitive() {
    XCTAssertEqual(SubtitleLanguage.parse(apiType: "SUBRU"), .ru)
    XCTAssertEqual(SubtitleLanguage.parse(apiType: "SubEn"), .en)
  }

  func test_parse_unknown_returnsOther() {
    XCTAssertEqual(SubtitleLanguage.parse(apiType: "subPt"), .other("subPt"))
    XCTAssertEqual(SubtitleLanguage.parse(apiType: "voiceRu"), .other("voiceRu"))
  }

  func test_parse_empty_returnsNil() {
    XCTAssertNil(SubtitleLanguage.parse(apiType: ""))
  }

  // MARK: - apiToken

  func test_apiToken_knownCases() {
    XCTAssertEqual(SubtitleLanguage.ru.apiToken, "subru")
    XCTAssertEqual(SubtitleLanguage.en.apiToken, "suben")
    XCTAssertEqual(SubtitleLanguage.uk.apiToken, "subuk")
    XCTAssertEqual(SubtitleLanguage.ja.apiToken, "subja")
    XCTAssertEqual(SubtitleLanguage.de.apiToken, "subde")
    XCTAssertEqual(SubtitleLanguage.fr.apiToken, "subfr")
    XCTAssertEqual(SubtitleLanguage.es.apiToken, "subes")
    XCTAssertEqual(SubtitleLanguage.zh.apiToken, "subzh")
    XCTAssertEqual(SubtitleLanguage.ko.apiToken, "subko")
  }

  func test_apiToken_other_lowercased() {
    XCTAssertEqual(SubtitleLanguage.other("subPT").apiToken, "subpt")
  }

  // MARK: - groupTitle

  func test_groupTitle_ru() {
    XCTAssertEqual(SubtitleLanguage.ru.groupTitle, "РУССКИЕ")
  }

  func test_groupTitle_en() {
    XCTAssertEqual(SubtitleLanguage.en.groupTitle, "АНГЛИЙСКИЕ")
  }

  func test_groupTitle_other_uppercased() {
    XCTAssertEqual(SubtitleLanguage.other("subPt").groupTitle, "SUBPT")
  }

  // MARK: - fallbackLabel

  func test_fallbackLabel_ru() {
    XCTAssertEqual(SubtitleLanguage.ru.fallbackLabel, "Русские субтитры")
  }

  func test_fallbackLabel_en() {
    XCTAssertEqual(SubtitleLanguage.en.fallbackLabel, "English subtitles")
  }

  func test_fallbackLabel_uk() {
    XCTAssertEqual(SubtitleLanguage.uk.fallbackLabel, "Українські субтитри")
  }

  // MARK: - SubtitleTrack.make uses SubtitleLanguage

  func test_trackMake_setsLanguageFromCandidate() {
    let candidate = SubtitleCandidate(
      translationId: 1,
      type: "subRu",
      typeKind: "sub",
      title: nil,
      authorsSummary: nil,
      assURL: URL(string: "https://cdn.example.com/1.ass")!,
      vttURL: URL(string: "https://cdn.example.com/1.vtt")!
    )
    let track = SubtitleTrack.make(from: candidate)
    XCTAssertEqual(track.language, .ru)
    XCTAssertEqual(track.studioName, "Русские субтитры")
  }

  func test_trackMake_usesAuthorsSummaryWhenPresent() {
    let candidate = SubtitleCandidate(
      translationId: 2,
      type: "subEn",
      typeKind: "sub",
      title: nil,
      authorsSummary: "Crunchyroll",
      assURL: URL(string: "https://cdn.example.com/2.ass")!,
      vttURL: URL(string: "https://cdn.example.com/2.vtt")!
    )
    let track = SubtitleTrack.make(from: candidate)
    XCTAssertEqual(track.language, .en)
    XCTAssertEqual(track.studioName, "Crunchyroll")
  }
}
