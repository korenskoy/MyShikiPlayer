//
//  SubtitleColorCodec.swift
//  MyShikiPlayer
//
//  Encodes/decodes SwiftUI Color to/from "#RRGGBB" hex strings for UserDefaults storage.
//  Alpha is intentionally excluded — opacity is managed by a separate slider.
//

import SwiftUI
import AppKit

// MARK: - Color hex extension

extension Color {

  /// Parses a "#RRGGBB" or "RRGGBB" string (case-insensitive) into a SwiftUI Color.
  /// Returns nil on malformed input.
  init?(hexString: String) {
    var trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("#") { trimmed = String(trimmed.dropFirst()) }
    guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else { return nil }
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
  }

  /// Returns "#RRGGBB" in sRGB. Falls back to "#000000" when sRGB conversion fails.
  var hexString: String {
    let ns = NSColor(self).usingColorSpace(.sRGB) ?? .black
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ns.getRed(&r, green: &g, blue: &b, alpha: &a)
    let ri = Int((r * 255).rounded())
    let gi = Int((g * 255).rounded())
    let bi = Int((b * 255).rounded())
    return String(format: "#%02X%02X%02X", ri, gi, bi)
  }
}

// MARK: - Backward-compatibility shim

/// Retained so existing call sites compile without changes during migration.
/// New code should call `Color(hexString:)` / `.hexString` directly.
enum SubtitleColorCodec: Sendable {
  static func encode(_ color: Color) -> String { color.hexString }
  static func decode(_ hex: String) -> Color? { Color(hexString: hex) }
}
