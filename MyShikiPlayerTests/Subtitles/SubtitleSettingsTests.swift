//
//  SubtitleSettingsTests.swift
//  MyShikiPlayerTests
//

import XCTest
import AppKit
import SwiftUI
@testable import MyShikiPlayer

@MainActor
final class SubtitleSettingsTests: XCTestCase {

  private var suiteName: String!
  private var defaults: UserDefaults!
  private var settings: SubtitleSettings!

  override func setUp() async throws {
    try await super.setUp()
    suiteName = "test.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suiteName)!
    settings = SubtitleSettings(defaults: defaults)
  }

  override func tearDown() async throws {
    defaults.removePersistentDomain(forName: suiteName)
    try await super.tearDown()
  }

  // MARK: - Default values

  func test_defaults_preferredLanguage() {
    XCTAssertEqual(settings.preferredLanguage, .auto)
  }

  func test_defaults_useStudioStyle() {
    XCTAssertTrue(settings.useStudioStyle)
  }

  func test_defaults_fontFamily() {
    XCTAssertEqual(settings.fontFamily, "SF Pro Display")
  }

  func test_defaults_fontSize() {
    XCTAssertEqual(settings.fontSize, 28)
  }

  func test_defaults_fontWeight() {
    XCTAssertEqual(settings.fontWeight, .semibold)
  }

  func test_defaults_textColor() {
    let encoded = SubtitleColorCodec.encode(settings.textColor)
    XCTAssertEqual(encoded.uppercased(), "#FFFFFF")
  }

  func test_defaults_outlineColor() {
    let encoded = SubtitleColorCodec.encode(settings.outlineColor)
    XCTAssertEqual(encoded.uppercased(), "#000000")
  }

  func test_defaults_outlineWidth() {
    XCTAssertEqual(settings.outlineWidth, 2.0)
  }

  func test_defaults_shadowEnabled() {
    XCTAssertTrue(settings.shadowEnabled)
  }

  func test_defaults_backgroundStyle() {
    XCTAssertEqual(settings.backgroundStyle, .shadow)
  }

  func test_defaults_backgroundOpacity() {
    XCTAssertEqual(settings.backgroundOpacity, 0.35, accuracy: 0.001)
  }

  func test_defaults_verticalPosition() {
    XCTAssertEqual(settings.verticalPosition, 0.92, accuracy: 0.001)
  }

  func test_defaults_maxLines() {
    XCTAssertEqual(settings.maxLines, 3)
  }

  // MARK: - Write and readback

  func test_write_preferredLanguage_persists() {
    settings.preferredLanguage = .subEn
    XCTAssertEqual(SubtitleSettings(defaults: defaults).preferredLanguage, .subEn)
  }

  func test_write_useStudioStyle_persists() {
    settings.useStudioStyle = false
    XCTAssertFalse(SubtitleSettings(defaults: defaults).useStudioStyle)
  }

  func test_write_fontFamily_persists() {
    settings.fontFamily = "Helvetica Neue"
    XCTAssertEqual(SubtitleSettings(defaults: defaults).fontFamily, "Helvetica Neue")
  }

  func test_write_fontSize_persists() {
    settings.fontSize = 36.0
    XCTAssertEqual(SubtitleSettings(defaults: defaults).fontSize, 36.0, accuracy: 0.001)
  }

  func test_write_fontWeight_persists() {
    settings.fontWeight = .bold
    XCTAssertEqual(SubtitleSettings(defaults: defaults).fontWeight, .bold)
  }

  func test_write_textColor_persists() {
    settings.textColor = SubtitleColorCodec.decode("#FF0000")!
    let hex = SubtitleColorCodec.encode(SubtitleSettings(defaults: defaults).textColor)
    XCTAssertEqual(hex.uppercased(), "#FF0000")
  }

  func test_write_outlineColor_persists() {
    settings.outlineColor = SubtitleColorCodec.decode("#3A7FCC")!
    let hex = SubtitleColorCodec.encode(SubtitleSettings(defaults: defaults).outlineColor)
    XCTAssertEqual(hex.uppercased(), "#3A7FCC")
  }

  func test_write_outlineWidth_persists() {
    settings.outlineWidth = 4.5
    XCTAssertEqual(SubtitleSettings(defaults: defaults).outlineWidth, 4.5, accuracy: 0.001)
  }

  func test_write_shadowEnabled_persists() {
    settings.shadowEnabled = false
    XCTAssertFalse(SubtitleSettings(defaults: defaults).shadowEnabled)
  }

  func test_write_backgroundStyle_persists() {
    settings.backgroundStyle = .box
    XCTAssertEqual(SubtitleSettings(defaults: defaults).backgroundStyle, .box)
  }

  func test_write_backgroundOpacity_persists() {
    settings.backgroundOpacity = 0.75
    XCTAssertEqual(SubtitleSettings(defaults: defaults).backgroundOpacity, 0.75, accuracy: 0.001)
  }

  func test_write_verticalPosition_persists() {
    settings.verticalPosition = 0.80
    XCTAssertEqual(SubtitleSettings(defaults: defaults).verticalPosition, 0.80, accuracy: 0.001)
  }

  func test_write_maxLines_persists() {
    settings.maxLines = 5
    XCTAssertEqual(SubtitleSettings(defaults: defaults).maxLines, 5)
  }

  // MARK: - resetToDefaults

  func test_resetToDefaults_restoresAllKeys() {
    settings.preferredLanguage = .subRu
    settings.useStudioStyle = false
    settings.fontFamily = "Arial"
    settings.fontSize = 40
    settings.fontWeight = .heavy
    settings.textColor = SubtitleColorCodec.decode("#FF0000")!
    settings.outlineColor = SubtitleColorCodec.decode("#3A7FCC")!
    settings.outlineWidth = 6.0
    settings.shadowEnabled = false
    settings.backgroundStyle = .box
    settings.backgroundOpacity = 0.9
    settings.verticalPosition = 0.5
    settings.maxLines = 1

    settings.resetToDefaults()

    let fresh = SubtitleSettings(defaults: defaults)
    XCTAssertEqual(fresh.preferredLanguage, .auto)
    XCTAssertTrue(fresh.useStudioStyle)
    XCTAssertEqual(fresh.fontFamily, "SF Pro Display")
    XCTAssertEqual(fresh.fontSize, 28, accuracy: 0.001)
    XCTAssertEqual(fresh.fontWeight, .semibold)
    XCTAssertEqual(SubtitleColorCodec.encode(fresh.textColor).uppercased(), "#FFFFFF")
    XCTAssertEqual(SubtitleColorCodec.encode(fresh.outlineColor).uppercased(), "#000000")
    XCTAssertEqual(fresh.outlineWidth, 2.0, accuracy: 0.001)
    XCTAssertTrue(fresh.shadowEnabled)
    XCTAssertEqual(fresh.backgroundStyle, .shadow)
    XCTAssertEqual(fresh.backgroundOpacity, 0.35, accuracy: 0.001)
    XCTAssertEqual(fresh.verticalPosition, 0.92, accuracy: 0.001)
    XCTAssertEqual(fresh.maxLines, 3)
  }

  func test_resetToDefaults_doesNotTouchOtherKeys() {
    defaults.set("custom_value", forKey: "some.unrelated.key")
    settings.resetToDefaults()
    XCTAssertEqual(defaults.string(forKey: "some.unrelated.key"), "custom_value")
  }

  // MARK: - resolvedAPILanguageFilter

  func test_resolvedAPILanguageFilter_auto_russianLocale() {
    settings.preferredLanguage = .auto
    let result = settings.resolvedAPILanguageFilter(locale: Locale(identifier: "ru_RU"))
    XCTAssertEqual(result, "subru")
  }

  func test_resolvedAPILanguageFilter_auto_englishLocale() {
    settings.preferredLanguage = .auto
    let result = settings.resolvedAPILanguageFilter(locale: Locale(identifier: "en_US"))
    XCTAssertEqual(result, "suben")
  }

  func test_resolvedAPILanguageFilter_auto_japaneseLocale() {
    settings.preferredLanguage = .auto
    let result = settings.resolvedAPILanguageFilter(locale: Locale(identifier: "ja_JP"))
    XCTAssertEqual(result, "suben")
  }

  func test_resolvedAPILanguageFilter_subRu() {
    settings.preferredLanguage = .subRu
    XCTAssertEqual(settings.resolvedAPILanguageFilter(locale: Locale(identifier: "en_US")), "subru")
  }

  func test_resolvedAPILanguageFilter_subEn() {
    settings.preferredLanguage = .subEn
    XCTAssertEqual(settings.resolvedAPILanguageFilter(locale: Locale(identifier: "ru_RU")), "suben")
  }

  func test_resolvedAPILanguageFilter_off() {
    settings.preferredLanguage = .off
    XCTAssertNil(settings.resolvedAPILanguageFilter(locale: Locale(identifier: "ru_RU")))
  }
}

// MARK: - SubtitleColorCodecTests

final class SubtitleColorCodecTests: XCTestCase {

  private let tolerance: CGFloat = 1.0 / 255.0

  // MARK: - Roundtrip

  func test_roundtrip_white() {
    assertRoundtrip("#FFFFFF", r: 1, g: 1, b: 1)
  }

  func test_roundtrip_black() {
    assertRoundtrip("#000000", r: 0, g: 0, b: 0)
  }

  func test_roundtrip_red() {
    assertRoundtrip("#FF0000", r: 1, g: 0, b: 0)
  }

  func test_roundtrip_nonTrivial() {
    // #3A7FCC = r:0x3A/255, g:0x7F/255, b:0xCC/255
    assertRoundtrip("#3A7FCC", r: 0x3A / 255.0, g: 0x7F / 255.0, b: 0xCC / 255.0)
  }

  // MARK: - Decode tolerates no-hash prefix

  func test_decode_withoutHash() {
    let color = SubtitleColorCodec.decode("FF0000")
    XCTAssertNotNil(color)
    let ns = NSColor(color!).usingColorSpace(.sRGB)!
    XCTAssertEqual(ns.redComponent, 1.0, accuracy: tolerance)
  }

  func test_decode_lowercaseHex() {
    let color = SubtitleColorCodec.decode("#3a7fcc")
    XCTAssertNotNil(color)
    let ns = NSColor(color!).usingColorSpace(.sRGB)!
    XCTAssertEqual(ns.redComponent, CGFloat(0x3A) / 255.0, accuracy: tolerance)
    XCTAssertEqual(ns.greenComponent, CGFloat(0x7F) / 255.0, accuracy: tolerance)
    XCTAssertEqual(ns.blueComponent, CGFloat(0xCC) / 255.0, accuracy: tolerance)
  }

  // MARK: - Bad input

  func test_decode_badInput_returnsNil() {
    XCTAssertNil(SubtitleColorCodec.decode("#XYZ"))
    XCTAssertNil(SubtitleColorCodec.decode(""))
    XCTAssertNil(SubtitleColorCodec.decode("#12"))
    XCTAssertNil(SubtitleColorCodec.decode("#GGGGGG"))
    XCTAssertNil(SubtitleColorCodec.decode("#1234567"))
  }

  // MARK: - SettingsKeys completeness

  func test_settingsKeys_allSubtitleKeysExist() {
    XCTAssertFalse(SettingsKeys.subtitlesPreferredLanguage.isEmpty)
    XCTAssertFalse(SettingsKeys.subtitlesUseStudioStyle.isEmpty)
    XCTAssertFalse(SettingsKeys.subtitlesFontFamily.isEmpty)
    XCTAssertFalse(SettingsKeys.subtitlesFontSize.isEmpty)
    XCTAssertFalse(SettingsKeys.subtitlesFontWeight.isEmpty)
    XCTAssertFalse(SettingsKeys.subtitlesTextColor.isEmpty)
    XCTAssertFalse(SettingsKeys.subtitlesOutlineColor.isEmpty)
    XCTAssertFalse(SettingsKeys.subtitlesOutlineWidth.isEmpty)
    XCTAssertFalse(SettingsKeys.subtitlesShadowEnabled.isEmpty)
    XCTAssertFalse(SettingsKeys.subtitlesBackgroundStyle.isEmpty)
    XCTAssertFalse(SettingsKeys.subtitlesBackgroundOpacity.isEmpty)
    XCTAssertFalse(SettingsKeys.subtitlesVerticalPosition.isEmpty)
    XCTAssertFalse(SettingsKeys.subtitlesMaxLines.isEmpty)
  }

  // MARK: - Helpers

  private func assertRoundtrip(
    _ hex: String,
    r expectedR: CGFloat,
    g expectedG: CGFloat,
    b expectedB: CGFloat,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    guard let decoded = SubtitleColorCodec.decode(hex) else {
      XCTFail("Decode returned nil for \(hex)", file: file, line: line)
      return
    }
    let ns = NSColor(decoded).usingColorSpace(.sRGB)!
    XCTAssertEqual(ns.redComponent, expectedR, accuracy: tolerance, file: file, line: line)
    XCTAssertEqual(ns.greenComponent, expectedG, accuracy: tolerance, file: file, line: line)
    XCTAssertEqual(ns.blueComponent, expectedB, accuracy: tolerance, file: file, line: line)

    let reEncoded = SubtitleColorCodec.encode(decoded)
    XCTAssertEqual(reEncoded.uppercased(), hex.uppercased(), file: file, line: line)
  }
}
