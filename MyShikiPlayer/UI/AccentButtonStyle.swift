//
//  AccentButtonStyle.swift
//  MyShikiPlayer
//

import SwiftUI

/// Primary accent-filled button: stays readable on macOS when the window is unfocused
/// (unlike `borderedProminent`, which nearly vanishes in an inactive window).
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.55))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillColor(isPressed: configuration.isPressed))
            )
            .opacity(isEnabled ? 1 : 0.85)
    }

    private func fillColor(isPressed: Bool) -> Color {
        let base = Color.accentColor
        if !isEnabled {
            return base.opacity(0.42)
        }
        return base.opacity(isPressed ? 0.82 : 1)
    }
}

extension ButtonStyle where Self == AccentButtonStyle {
    static var accent: AccentButtonStyle { AccentButtonStyle() }
}
