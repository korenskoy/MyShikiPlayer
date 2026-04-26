//
//  DSChip.swift
//  MyShikiPlayer
//
//  Pill-shaped tag button. Supports active/inactive, sm/md sizes, mono variant.
//  Equivalent of Chip from primitives.jsx.
//

import SwiftUI

struct DSChip: View {
    enum Size { case small, medium }

    @Environment(\.appTheme) private var theme

    let title: String
    var isActive: Bool = false
    var size: Size = .medium
    var mono: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .tracking(mono ? 0.4 : 0)
                .padding(.horizontal, size == .small ? 8 : 10)
                .padding(.vertical, size == .small ? 4 : 6)
                .foregroundStyle(foreground)
                .background(
                    Capsule(style: .continuous)
                        .fill(background)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(border, lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.12), value: isActive)
        }
        .buttonStyle(.plain)
    }

    private var font: Font {
        let s: CGFloat = size == .small ? 11 : 12
        let w: Font.Weight = isActive ? .semibold : .medium
        return mono ? .dsMono(s, weight: w) : .dsBody(s, weight: w)
    }

    private var foreground: Color {
        if isActive {
            return theme.mode == .dark ? Color(hex: 0x0B0A0D) : .white
        }
        return theme.fg2
    }

    private var background: Color {
        isActive ? theme.accent : theme.chipBg
    }

    private var border: Color {
        isActive ? theme.accent : theme.chipBr
    }
}

#if DEBUG
#Preview("Chip states") {
    HStack(spacing: 8) {
        DSChip(title: "Все")
        DSChip(title: "Смотрю", isActive: true)
        DSChip(title: "2025", size: .small, mono: true)
        DSChip(title: "Онгоинг", mono: true)
    }
    .padding(24)
    .background(AppTheme.paper.bg)
    .appTheme(.paper)
}
#endif
