//
//  AppTheme.swift
//  MyShikiPlayer
//
//  Palettes from myshikiplayer_design_reference/project/themes.jsx.
//
//  Two paired families:
//      Otaku  — midnight (dark) ↔ paper (light)   — red/coral accent
//      Plum   — plum (dark) ↔ slate (light)       — cyan accent
//
//  Auto themes (`auto.otaku`, `auto.plum`) follow the system appearance and
//  switch between the dark and light family member.
//
//  The player always uses .midnight regardless of the selected app theme.
//

import SwiftUI

struct AppTheme: Equatable {
    enum Mode { case light, dark }

    let id: String
    let name: String
    let mode: Mode

    // Surfaces
    let bg: Color
    let bg2: Color
    let bg3: Color
    let card: Color

    // Borders
    let line: Color
    let line2: Color

    // Text
    let fg: Color
    let fg2: Color
    let fg3: Color

    // Accents
    let accent: Color
    let accent2: Color
    let good: Color
    let warn: Color
    let violet: Color

    // Chip / controls
    let chipBg: Color
    let chipBr: Color

    // Glow (for box-shadow and focus ring)
    let glow: Color
}

// MARK: - Palettes

extension AppTheme {
    static let midnight = AppTheme(
        id: "midnight",
        name: "Midnight Otaku",
        mode: .dark,
        bg:      Color(hex: 0x0B0A0D),
        bg2:     Color(hex: 0x141218),
        bg3:     Color(hex: 0x1D1A22),
        card:    Color(hex: 0x17151B),
        line:    Color.white.opacity(0.08),
        line2:   Color.white.opacity(0.14),
        fg:      Color(hex: 0xF5F1EA),
        fg2:     Color(hex: 0xF5F1EA, opacity: 0.72),
        fg3:     Color(hex: 0xF5F1EA, opacity: 0.48),
        accent:  Color(hex: 0xFF4D5E),
        accent2: Color(hex: 0xFFB199),
        good:    Color(hex: 0x7CD992),
        warn:    Color(hex: 0xFFC857),
        violet:  Color(hex: 0x9A7BFF),
        chipBg:  Color.white.opacity(0.06),
        chipBr:  Color.white.opacity(0.12),
        glow:    Color(hex: 0xFF4D5E)
    )

    static let plum = AppTheme(
        id: "plum",
        name: "Neon Plum",
        mode: .dark,
        bg:      Color(hex: 0x0E0B16),
        bg2:     Color(hex: 0x17102A),
        bg3:     Color(hex: 0x201736),
        card:    Color(hex: 0x150E24),
        line:    Color.white.opacity(0.10),
        line2:   Color.white.opacity(0.18),
        fg:      Color(hex: 0xF0EAFF),
        fg2:     Color(hex: 0xF0EAFF, opacity: 0.72),
        fg3:     Color(hex: 0xF0EAFF, opacity: 0.48),
        accent:  Color(hex: 0x00E3FF),
        accent2: Color(hex: 0xFF3DC7),
        good:    Color(hex: 0x5CF0A8),
        warn:    Color(hex: 0xFFD23F),
        violet:  Color(hex: 0xB88CFF),
        chipBg:  Color.white.opacity(0.07),
        chipBr:  Color.white.opacity(0.14),
        glow:    Color(hex: 0x00E3FF)
    )

    static let paper = AppTheme(
        id: "paper",
        name: "Daylight Otaku",
        mode: .light,
        bg:      Color(hex: 0xFBFAF7),
        bg2:     Color(hex: 0xF1EFE9),
        bg3:     Color(hex: 0xE7E4DC),
        card:    Color(hex: 0xFFFFFF),
        line:    Color(hex: 0x0B0A0D, opacity: 0.10),
        line2:   Color(hex: 0x0B0A0D, opacity: 0.18),
        fg:      Color(hex: 0x0B0A0D),
        fg2:     Color(hex: 0x0B0A0D, opacity: 0.70),
        fg3:     Color(hex: 0x0B0A0D, opacity: 0.45),
        accent:  Color(hex: 0xFF4D5E),
        accent2: Color(hex: 0xFFB199),
        good:    Color(hex: 0x3D8A55),
        warn:    Color(hex: 0xC28A1D),
        violet:  Color(hex: 0x6B4AC9),
        chipBg:  Color(hex: 0x0B0A0D, opacity: 0.05),
        chipBr:  Color(hex: 0x0B0A0D, opacity: 0.12),
        glow:    Color(hex: 0xFF4D5E)
    )

    static let slate = AppTheme(
        id: "slate",
        name: "Daylight Plum",
        mode: .light,
        bg:      Color(hex: 0xF6F3FB),
        bg2:     Color(hex: 0xECE6F4),
        bg3:     Color(hex: 0xDDD3EA),
        card:    Color(hex: 0xFDFBFF),
        line:    Color(hex: 0x140C28, opacity: 0.10),
        line2:   Color(hex: 0x140C28, opacity: 0.18),
        fg:      Color(hex: 0x1A1230),
        fg2:     Color(hex: 0x1A1230, opacity: 0.70),
        fg3:     Color(hex: 0x1A1230, opacity: 0.46),
        accent:  Color(hex: 0x0099B3),
        accent2: Color(hex: 0xD62AA2),
        good:    Color(hex: 0x1F8A55),
        warn:    Color(hex: 0xB07A12),
        violet:  Color(hex: 0x6B3EC9),
        chipBg:  Color(hex: 0x140C28, opacity: 0.05),
        chipBr:  Color(hex: 0x140C28, opacity: 0.12),
        glow:    Color(hex: 0x0099B3)
    )

    /// Concrete palettes available for direct selection (and for resolving
    /// auto-pair ids into a real theme).
    static let allFixed: [AppTheme] = [.midnight, .plum, .paper, .slate]

    /// Auto-pair ids — virtual themes whose actual palette depends on the
    /// system appearance.
    static let autoOtakuId = "auto.otaku"
    static let autoPlumId = "auto.plum"
    static let autoIds: [String] = [autoOtakuId, autoPlumId]

    static func byId(_ id: String) -> AppTheme {
        allFixed.first { $0.id == id } ?? .midnight
    }

    /// Resolve a stored theme id to a concrete palette, honouring the active
    /// system color scheme for `auto.*` ids.
    static func resolve(id: String, systemScheme: ColorScheme) -> AppTheme {
        switch id {
        case autoOtakuId: return systemScheme == .dark ? .midnight : .paper
        case autoPlumId:  return systemScheme == .dark ? .plum : .slate
        default:          return byId(id)
        }
    }

    /// Human-readable name for any selectable id (including `auto.*`).
    static func displayName(for id: String) -> String {
        switch id {
        case autoOtakuId: return "Авто · Otaku"
        case autoPlumId:  return "Авто · Plum"
        default:          return byId(id).name
        }
    }
}

// MARK: - Environment

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .midnight
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

extension View {
    /// Injects the theme into the environment and synchronously applies ColorScheme (for system controls).
    func appTheme(_ theme: AppTheme) -> some View {
        self
            .environment(\.appTheme, theme)
            .environment(\.colorScheme, theme.mode == .dark ? .dark : .light)
    }
}

// MARK: - Color hex helper

extension Color {
    /// `Color(hex: 0xFF4D5E)` — RGB from a 24-bit hex value.
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
