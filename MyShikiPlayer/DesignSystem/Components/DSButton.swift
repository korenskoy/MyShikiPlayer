//
//  DSButton.swift
//  MyShikiPlayer
//
//  Button with primary / secondary / ghost / outline variants.
//  Equivalent of Button() from primitives.jsx.
//

import SwiftUI

struct DSButton<Label: View>: View {
    enum Variant { case primary, secondary, ghost, outline }
    enum Size { case small, medium, large }

    @Environment(\.appTheme) private var theme

    var variant: Variant = .primary
    var size: Size = .medium
    var iconName: DSIconName? = nil
    var fullWidth: Bool = false
    var isLoading: Bool = false
    let action: () -> Void
    let label: Label

    init(
        variant: Variant = .primary,
        size: Size = .medium,
        icon: DSIconName? = nil,
        fullWidth: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.variant = variant
        self.size = size
        self.iconName = icon
        self.fullWidth = fullWidth
        self.isLoading = isLoading
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(action: { if !isLoading { action() } }) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .progressViewStyle(.circular)
                        .tint(foregroundColor)
                        .frame(width: iconSize, height: iconSize)
                } else if let iconName {
                    DSIcon(name: iconName, size: iconSize, weight: .semibold)
                }
                label
            }
            .font(.dsBody(fontSize, weight: .semibold))
            .tracking(0.1)
            .foregroundStyle(foregroundColor)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .opacity(isLoading ? 0.85 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var horizontalPadding: CGFloat {
        switch size { case .small: 12; case .medium: 16; case .large: 20 }
    }
    private var verticalPadding: CGFloat {
        switch size { case .small: 7; case .medium: 9; case .large: 12 }
    }
    private var fontSize: CGFloat {
        switch size { case .small: 12; case .medium: 13; case .large: 14 }
    }
    private var iconSize: CGFloat { fontSize + 2 }

    private var foregroundColor: Color {
        switch variant {
        case .primary:   return theme.mode == .dark ? Color(hex: 0x0B0A0D) : .white
        case .secondary, .ghost, .outline: return theme.fg
        }
    }

    private var backgroundColor: Color {
        switch variant {
        case .primary:   return theme.accent
        case .secondary: return theme.chipBg
        case .ghost, .outline: return .clear
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary: return .clear
        case .secondary: return theme.chipBr
        case .ghost: return .clear
        case .outline: return theme.line2
        }
    }
}

// Text-only convenience init.
extension DSButton where Label == Text {
    init(
        _ title: String,
        variant: Variant = .primary,
        size: Size = .medium,
        icon: DSIconName? = nil,
        fullWidth: Bool = false,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            variant: variant,
            size: size,
            icon: icon,
            fullWidth: fullWidth,
            isLoading: isLoading,
            action: action
        ) {
            Text(title)
        }
    }
}
