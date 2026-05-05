//
//  ScrollTopButton.swift
//  MyShikiPlayer
//
//  Floating "scroll to top" pill used in the social feed and topic detail
//  scroll views. Rendered as an overlay on top of the parent ScrollView so
//  it stays anchored to the viewport's bottom-trailing corner regardless of
//  scroll offset.
//
//  Visibility is driven by the parent (via `onScrollGeometryChange` with a
//  hysteresis pair) — this view is purely presentational so the same
//  threshold logic doesn't have to be re-implemented per call site.
//

import SwiftUI

struct ScrollTopButton: View {
    @Environment(\.appTheme) private var theme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DSIcon(name: .arrowUp, size: 14, weight: .semibold)
                .foregroundStyle(theme.fg)
                .frame(width: 38, height: 38)
                .background(Circle().fill(theme.chipBg))
                .overlay(Circle().stroke(theme.line, lineWidth: 1))
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .help("Наверх")
    }
}

/// Hysteresis thresholds shared by both scroll-to-top callers so the chip
/// appears and hides at the same offsets across the app.
enum ScrollTopThresholds {
    static let show: CGFloat = 600
    static let hide: CGFloat = 400

    /// Returns the new visibility given the previous state and the current
    /// scroll offset. Centralised so both callers stay in sync.
    static func shouldShow(previous: Bool, offset: CGFloat) -> Bool {
        offset > (previous ? hide : show)
    }
}
