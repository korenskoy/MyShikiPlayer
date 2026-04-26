//
//  DSPlayerPill.swift
//  MyShikiPlayer
//
//  Player-specific pill: "DUB · StudioBand", "SUB · Russian", "1080p", "x1.0".
//  Equivalent of PlayerPill from screens-player.jsx. Always uses translucent white
//  over dark video — this is a player component, not general UI.
//

import SwiftUI

struct DSPlayerPill: View {
    let label: String
    var value: String? = nil
    var icon: DSIconName? = nil
    var showsChevron: Bool = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    DSIcon(name: icon, size: 13, weight: .regular)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                Text(label)
                    .font(.dsMono(10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Color.white.opacity(0.55))
                if let value, !value.isEmpty {
                    Text(value)
                        .font(.dsBody(11, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                if showsChevron {
                    DSIcon(name: .chevD, size: 10, weight: .regular)
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Round icon button on the dark player background. Equivalent of IconButton from screens-player.jsx.
struct DSPlayerIconButton: View {
    let icon: DSIconName
    var flipHorizontally: Bool = false
    var size: CGFloat = 36
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            DSIcon(name: icon, size: 16, weight: .semibold)
                .foregroundStyle(Color.white)
                .scaleEffect(x: flipHorizontally ? -1 : 1, y: 1)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}
