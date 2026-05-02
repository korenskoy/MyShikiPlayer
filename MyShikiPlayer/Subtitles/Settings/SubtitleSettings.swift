//
//  SubtitleSettings.swift
//  MyShikiPlayer
//
//  UserDefaults-backed settings model for subtitle display.
//  Drives both SwiftUI views (Phase 6) and non-view renderers (Phase 4).
//

import SwiftUI
import Observation

// MARK: - Enums

enum SubtitlePreferredLanguage: String, CaseIterable, Sendable {
  case auto
  case subRu
  case subEn
  case off
}

enum SubtitleFontWeight: String, CaseIterable, Sendable {
  case regular
  case medium
  case semibold
  case bold
  case heavy

  var swiftUIWeight: Font.Weight {
    switch self {
    case .regular:  return .regular
    case .medium:   return .medium
    case .semibold: return .semibold
    case .bold:     return .bold
    case .heavy:    return .heavy
    }
  }
}

enum SubtitleBackgroundStyle: String, CaseIterable, Sendable {
  case none
  case shadow
  case box
}

// MARK: - Defaults

private enum Defaults {
  static let preferredLanguage = SubtitlePreferredLanguage.auto
  static let useStudioStyle = true
  static let fontFamily = "SF Pro Display"
  static let fontSize: Double = 28
  static let fontWeight = SubtitleFontWeight.semibold
  static let textColorHex = "#FFFFFF"
  static let outlineColorHex = "#000000"
  static let outlineWidth: Double = 2.0
  static let shadowEnabled = true
  static let backgroundStyle = SubtitleBackgroundStyle.shadow
  static let backgroundOpacity: Double = 0.35
  static let verticalPosition: Double = 0.92
  static let maxLines = 3
}

// MARK: - SubtitleSettings

/// Computed properties below explicitly call `access(keyPath:)` and `withMutation(keyPath:)`
/// so the @Observable macro's registrar tracks UserDefaults-backed reads and writes.
/// Each property has a private mirror that caches the decoded value to avoid re-reading
/// and re-decoding UserDefaults on every SwiftUI render pass.
@MainActor
@Observable
final class SubtitleSettings {

  static let shared = SubtitleSettings()

  // MARK: - Storage

  @ObservationIgnored
  private let defaults: UserDefaults

  // MARK: - Backing helper

  /// Encapsulates a lazily-populated in-memory mirror for one UserDefaults-backed property.
  /// `T` is the decoded Swift type. `read` decodes from defaults; `write` serialises to defaults.
  private struct Backing<T> {
    var cached: T?
    let read: (UserDefaults) -> T
    let write: (UserDefaults, T) -> Void

    mutating func get(from defaults: UserDefaults) -> T {
      if let cached { return cached }
      let value = read(defaults)
      cached = value
      return value
    }

    mutating func set(_ value: T, in defaults: UserDefaults) {
      cached = value
      write(defaults, value)
    }

    mutating func invalidate() {
      cached = nil
    }
  }

  // MARK: - Mirrors

  @ObservationIgnored
  private var _preferredLanguage = Backing<SubtitlePreferredLanguage>(
    read: { d in
      guard let raw = d.string(forKey: SettingsKeys.subtitlesPreferredLanguage),
            let v = SubtitlePreferredLanguage(rawValue: raw) else { return Defaults.preferredLanguage }
      return v
    },
    write: { d, v in d.set(v.rawValue, forKey: SettingsKeys.subtitlesPreferredLanguage) }
  )

  @ObservationIgnored
  private var _useStudioStyle = Backing<Bool>(
    read: { d in
      guard let stored = d.object(forKey: SettingsKeys.subtitlesUseStudioStyle) else {
        return Defaults.useStudioStyle
      }
      return (stored as? Bool) ?? Defaults.useStudioStyle
    },
    write: { d, v in d.set(v, forKey: SettingsKeys.subtitlesUseStudioStyle) }
  )

  @ObservationIgnored
  private var _fontFamily = Backing<String>(
    read: { d in d.string(forKey: SettingsKeys.subtitlesFontFamily) ?? Defaults.fontFamily },
    write: { d, v in d.set(v, forKey: SettingsKeys.subtitlesFontFamily) }
  )

  @ObservationIgnored
  private var _fontSize = Backing<Double>(
    read: { d in
      guard let stored = d.object(forKey: SettingsKeys.subtitlesFontSize) else { return Defaults.fontSize }
      if let v = stored as? Double { return v }
      if let v = stored as? Int { return Double(v) }
      return Defaults.fontSize
    },
    write: { d, v in d.set(v, forKey: SettingsKeys.subtitlesFontSize) }
  )

  @ObservationIgnored
  private var _fontWeight = Backing<SubtitleFontWeight>(
    read: { d in
      guard let raw = d.string(forKey: SettingsKeys.subtitlesFontWeight),
            let v = SubtitleFontWeight(rawValue: raw) else { return Defaults.fontWeight }
      return v
    },
    write: { d, v in d.set(v.rawValue, forKey: SettingsKeys.subtitlesFontWeight) }
  )

  @ObservationIgnored
  private var _textColor = Backing<Color>(
    read: { d in
      guard let hex = d.string(forKey: SettingsKeys.subtitlesTextColor) else { return .white }
      return Color(hexString: hex) ?? .white
    },
    write: { d, v in d.set(v.hexString, forKey: SettingsKeys.subtitlesTextColor) }
  )

  @ObservationIgnored
  private var _outlineColor = Backing<Color>(
    read: { d in
      guard let hex = d.string(forKey: SettingsKeys.subtitlesOutlineColor) else { return .black }
      return Color(hexString: hex) ?? .black
    },
    write: { d, v in d.set(v.hexString, forKey: SettingsKeys.subtitlesOutlineColor) }
  )

  @ObservationIgnored
  private var _outlineWidth = Backing<Double>(
    read: { d in
      guard let stored = d.object(forKey: SettingsKeys.subtitlesOutlineWidth) else {
        return Defaults.outlineWidth
      }
      if let v = stored as? Double { return v }
      if let v = stored as? Int { return Double(v) }
      return Defaults.outlineWidth
    },
    write: { d, v in d.set(v, forKey: SettingsKeys.subtitlesOutlineWidth) }
  )

  @ObservationIgnored
  private var _shadowEnabled = Backing<Bool>(
    read: { d in
      guard let stored = d.object(forKey: SettingsKeys.subtitlesShadowEnabled) else {
        return Defaults.shadowEnabled
      }
      return (stored as? Bool) ?? Defaults.shadowEnabled
    },
    write: { d, v in d.set(v, forKey: SettingsKeys.subtitlesShadowEnabled) }
  )

  @ObservationIgnored
  private var _backgroundStyle = Backing<SubtitleBackgroundStyle>(
    read: { d in
      guard let raw = d.string(forKey: SettingsKeys.subtitlesBackgroundStyle),
            let v = SubtitleBackgroundStyle(rawValue: raw) else { return Defaults.backgroundStyle }
      return v
    },
    write: { d, v in d.set(v.rawValue, forKey: SettingsKeys.subtitlesBackgroundStyle) }
  )

  @ObservationIgnored
  private var _backgroundOpacity = Backing<Double>(
    read: { d in
      guard let stored = d.object(forKey: SettingsKeys.subtitlesBackgroundOpacity) else {
        return Defaults.backgroundOpacity
      }
      if let v = stored as? Double { return v }
      if let v = stored as? Int { return Double(v) }
      return Defaults.backgroundOpacity
    },
    write: { d, v in d.set(v, forKey: SettingsKeys.subtitlesBackgroundOpacity) }
  )

  @ObservationIgnored
  private var _verticalPosition = Backing<Double>(
    read: { d in
      guard let stored = d.object(forKey: SettingsKeys.subtitlesVerticalPosition) else {
        return Defaults.verticalPosition
      }
      if let v = stored as? Double { return v }
      if let v = stored as? Int { return Double(v) }
      return Defaults.verticalPosition
    },
    write: { d, v in d.set(v, forKey: SettingsKeys.subtitlesVerticalPosition) }
  )

  @ObservationIgnored
  private var _maxLines = Backing<Int>(
    read: { d in
      guard let stored = d.object(forKey: SettingsKeys.subtitlesMaxLines) else { return Defaults.maxLines }
      if let v = stored as? Int { return v }
      if let v = stored as? Double { return Int(v) }
      return Defaults.maxLines
    },
    write: { d, v in d.set(v, forKey: SettingsKeys.subtitlesMaxLines) }
  )

  // MARK: - Init

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  // MARK: - Properties

  var preferredLanguage: SubtitlePreferredLanguage {
    get {
      access(keyPath: \.preferredLanguage)
      return _preferredLanguage.get(from: defaults)
    }
    set {
      withMutation(keyPath: \.preferredLanguage) {
        _preferredLanguage.set(newValue, in: defaults)
      }
    }
  }

  var useStudioStyle: Bool {
    get {
      access(keyPath: \.useStudioStyle)
      return _useStudioStyle.get(from: defaults)
    }
    set {
      withMutation(keyPath: \.useStudioStyle) {
        _useStudioStyle.set(newValue, in: defaults)
      }
    }
  }

  var fontFamily: String {
    get {
      access(keyPath: \.fontFamily)
      return _fontFamily.get(from: defaults)
    }
    set {
      withMutation(keyPath: \.fontFamily) {
        _fontFamily.set(newValue, in: defaults)
      }
    }
  }

  var fontSize: Double {
    get {
      access(keyPath: \.fontSize)
      return _fontSize.get(from: defaults)
    }
    set {
      withMutation(keyPath: \.fontSize) {
        _fontSize.set(newValue, in: defaults)
      }
    }
  }

  var fontWeight: SubtitleFontWeight {
    get {
      access(keyPath: \.fontWeight)
      return _fontWeight.get(from: defaults)
    }
    set {
      withMutation(keyPath: \.fontWeight) {
        _fontWeight.set(newValue, in: defaults)
      }
    }
  }

  var textColor: Color {
    get {
      access(keyPath: \.textColor)
      return _textColor.get(from: defaults)
    }
    set {
      withMutation(keyPath: \.textColor) {
        _textColor.set(newValue, in: defaults)
      }
    }
  }

  var outlineColor: Color {
    get {
      access(keyPath: \.outlineColor)
      return _outlineColor.get(from: defaults)
    }
    set {
      withMutation(keyPath: \.outlineColor) {
        _outlineColor.set(newValue, in: defaults)
      }
    }
  }

  var outlineWidth: Double {
    get {
      access(keyPath: \.outlineWidth)
      return _outlineWidth.get(from: defaults)
    }
    set {
      withMutation(keyPath: \.outlineWidth) {
        _outlineWidth.set(newValue, in: defaults)
      }
    }
  }

  var shadowEnabled: Bool {
    get {
      access(keyPath: \.shadowEnabled)
      return _shadowEnabled.get(from: defaults)
    }
    set {
      withMutation(keyPath: \.shadowEnabled) {
        _shadowEnabled.set(newValue, in: defaults)
      }
    }
  }

  var backgroundStyle: SubtitleBackgroundStyle {
    get {
      access(keyPath: \.backgroundStyle)
      return _backgroundStyle.get(from: defaults)
    }
    set {
      withMutation(keyPath: \.backgroundStyle) {
        _backgroundStyle.set(newValue, in: defaults)
      }
    }
  }

  var backgroundOpacity: Double {
    get {
      access(keyPath: \.backgroundOpacity)
      return _backgroundOpacity.get(from: defaults)
    }
    set {
      withMutation(keyPath: \.backgroundOpacity) {
        _backgroundOpacity.set(newValue, in: defaults)
      }
    }
  }

  var verticalPosition: Double {
    get {
      access(keyPath: \.verticalPosition)
      return _verticalPosition.get(from: defaults)
    }
    set {
      withMutation(keyPath: \.verticalPosition) {
        _verticalPosition.set(newValue, in: defaults)
      }
    }
  }

  var maxLines: Int {
    get {
      access(keyPath: \.maxLines)
      return _maxLines.get(from: defaults)
    }
    set {
      withMutation(keyPath: \.maxLines) {
        _maxLines.set(newValue, in: defaults)
      }
    }
  }

  // MARK: - Reset

  func resetToDefaults() {
    defaults.removeObject(forKey: SettingsKeys.subtitlesPreferredLanguage)
    defaults.removeObject(forKey: SettingsKeys.subtitlesUseStudioStyle)
    defaults.removeObject(forKey: SettingsKeys.subtitlesFontFamily)
    defaults.removeObject(forKey: SettingsKeys.subtitlesFontSize)
    defaults.removeObject(forKey: SettingsKeys.subtitlesFontWeight)
    defaults.removeObject(forKey: SettingsKeys.subtitlesTextColor)
    defaults.removeObject(forKey: SettingsKeys.subtitlesOutlineColor)
    defaults.removeObject(forKey: SettingsKeys.subtitlesOutlineWidth)
    defaults.removeObject(forKey: SettingsKeys.subtitlesShadowEnabled)
    defaults.removeObject(forKey: SettingsKeys.subtitlesBackgroundStyle)
    defaults.removeObject(forKey: SettingsKeys.subtitlesBackgroundOpacity)
    defaults.removeObject(forKey: SettingsKeys.subtitlesVerticalPosition)
    defaults.removeObject(forKey: SettingsKeys.subtitlesMaxLines)

    _preferredLanguage.invalidate()
    _useStudioStyle.invalidate()
    _fontFamily.invalidate()
    _fontSize.invalidate()
    _fontWeight.invalidate()
    _textColor.invalidate()
    _outlineColor.invalidate()
    _outlineWidth.invalidate()
    _shadowEnabled.invalidate()
    _backgroundStyle.invalidate()
    _backgroundOpacity.invalidate()
    _verticalPosition.invalidate()
    _maxLines.invalidate()
  }

  // MARK: - Language resolution

  /// Returns the typed language for the current preferredLanguage, resolved against the system locale.
  /// Returns nil when the user has disabled automatic subtitle selection.
  var resolvedLanguage: SubtitleLanguage? {
    resolvedLanguage(locale: Locale.current)
  }

  /// Overload that accepts an explicit locale for testing.
  func resolvedLanguage(locale: Locale) -> SubtitleLanguage? {
    switch preferredLanguage {
    case .off:
      return nil
    case .subRu:
      return .ru
    case .subEn:
      return .en
    case .auto:
      let lang = locale.language.languageCode?.identifier ?? ""
      return lang == "ru" ? .ru : .en
    }
  }

  /// String API-token form, kept for callers that still need it.
  var resolvedAPILanguageFilter: String? {
    resolvedAPILanguageFilter(locale: Locale.current)
  }

  /// Overload that accepts an explicit locale for testing.
  func resolvedAPILanguageFilter(locale: Locale) -> String? {
    resolvedLanguage(locale: locale)?.apiToken
  }
}
