//
//  AppTheme.swift
//  MyShikiPlayer
//
//  Paper / Midnight / Plum — palettes from myshikiplayer_design_reference/project/themes.jsx.
//  Default is paper. The player always uses .midnight regardless of the selected app theme.
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
    static let paper = AppTheme(
        id: "paper",
        name: "Paper Daylight",
        mode: .light,
        bg:      Color(hex: 0xF4EFE6),
        bg2:     Color(hex: 0xECE5D7),
        bg3:     Color(hex: 0xE2D9C6),
        card:    Color(hex: 0xFBF6EC),
        line:    Color(hex: 0x17130E, opacity: 0.12),
        line2:   Color(hex: 0x17130E, opacity: 0.22),
        fg:      Color(hex: 0x17130E),
        fg2:     Color(hex: 0x17130E, opacity: 0.70),
        fg3:     Color(hex: 0x17130E, opacity: 0.45),
        accent:  Color(hex: 0xD9412B),
        accent2: Color(hex: 0xD97757),
        good:    Color(hex: 0x3D8A55),
        warn:    Color(hex: 0xC28A1D),
        violet:  Color(hex: 0x6B4AC9),
        chipBg:  Color(hex: 0x17130E, opacity: 0.05),
        chipBr:  Color(hex: 0x17130E, opacity: 0.14),
        glow:    Color(hex: 0xD9412B)
    )

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

    static let all: [AppTheme] = [.paper, .midnight, .plum]

    static func byId(_ id: String) -> AppTheme {
        all.first { $0.id == id } ?? .paper
    }
}

// MARK: - Environment

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .paper
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
