//
//  ListStatusBadge.swift
//  MyShikiPlayer
//
//  User-list status marker for posters: a coloured dot in the corner that
//  expands on hover into a pill with the status name. A separate view so
//  that only posters which opt in observe the shared index — the rest don't
//  re-render when a status changes.
//

import SwiftUI

struct ListStatusBadge: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var index = MyListIndex.shared
    @State private var isHovered = false
    let animeId: Int

    var body: some View {
        // The index usually lands after the posters — fade the dot in instead
        // of popping it.
        ZStack {
            if let status = index.status(for: animeId) {
                badge(for: status)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: index.status(for: animeId))
    }

    private func badge(for status: MyListStatus) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color(for: status))
                .frame(width: 10, height: 10)

            if isHovered {
                Text(status.displayName)
                    .font(.dsBody(11, weight: .semibold))
                    .foregroundStyle(theme.fg)
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
            }
        }
        // Fixed height and leading inset: collapsed this is a 20pt disc, and
        // on hover only the trailing edge moves, so the dot stays in place.
        .padding(.leading, 5)
        .padding(.trailing, isHovered ? 8 : 5)
        .frame(height: 20)
        // The backdrop, not the dot, carries the contrast: a bare coloured dot
        // disappears on a poster of the same hue, a theme-coloured disc
        // doesn't. Same treatment as the score and episode chips.
        .background(
            Capsule(style: .continuous)
                .fill(theme.bg.opacity(0.9))
        )
        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1)
        // Slightly wider hover area than the disc itself.
        .padding(5)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.82)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.displayName)
    }

    private func color(for status: MyListStatus) -> Color {
        switch status {
        case .watching, .rewatching: return theme.accent
        case .planned:               return theme.violet
        case .completed:             return theme.good
        case .onHold:                return theme.warn
        case .dropped:               return theme.fg3
        }
    }
}
