//
//  DSSurface.swift
//  MyShikiPlayer
//
//  Card / surface with theme, border and rounded corners. Equivalent of Surface() from primitives.jsx.
//  Used as a background for panels, episode cards, settings sections, etc.
//

import SwiftUI

struct DSSurface<Content: View>: View {
    @Environment(\.appTheme) private var theme

    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 16
    var fillOverride: Color? = nil
    var strokeOverride: Color? = nil
    let content: Content

    init(
        padding: CGFloat = 20,
        cornerRadius: CGFloat = 16,
        fill: Color? = nil,
        stroke: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.fillOverride = fill
        self.strokeOverride = stroke
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillOverride ?? theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeOverride ?? theme.line, lineWidth: 1)
            )
    }
}

#if DEBUG
#Preview("Paper") {
    DSSurface {
        VStack(alignment: .leading, spacing: 8) {
            Text("Surface / card").font(.dsTitle(17))
            Text("Фон, рамка и скругление из темы.").font(.dsBody(13))
        }
    }
    .padding(24)
    .background(AppTheme.paper.bg)
    .appTheme(.paper)
    .frame(width: 400, height: 160)
}

#Preview("Midnight") {
    DSSurface {
        VStack(alignment: .leading, spacing: 8) {
            Text("Surface / card").font(.dsTitle(17)).foregroundStyle(AppTheme.midnight.fg)
            Text("Фон, рамка и скругление из темы.").font(.dsBody(13)).foregroundStyle(AppTheme.midnight.fg2)
        }
    }
    .padding(24)
    .background(AppTheme.midnight.bg)
    .appTheme(.midnight)
    .frame(width: 400, height: 160)
}
#endif
