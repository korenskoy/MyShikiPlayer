//
//  HUDTheme.swift
//  MyShikiPlayer
//

import SwiftUI

enum HUDTheme {
    static let cornerRadius: CGFloat = 14
    static let compactCornerRadius: CGFloat = 10
    static let panelPadding: CGFloat = 12
    static let chipHorizontalPadding: CGFloat = 10
    static let chipVerticalPadding: CGFloat = 6

    static func panelBackground(colorScheme: ColorScheme) -> AnyShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(.ultraThinMaterial)
        }
        return AnyShapeStyle(.regularMaterial)
    }

    static func borderColor(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08)
    }

    static func selectedChipBackground(_ tint: Color) -> Color {
        tint.opacity(0.24)
    }

    static func unselectedChipBackground(colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }
}
