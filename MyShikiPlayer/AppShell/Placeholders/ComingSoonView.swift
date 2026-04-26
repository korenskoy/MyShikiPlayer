//
//  ComingSoonView.swift
//  MyShikiPlayer
//
//  Placeholder screen for tabs that are not yet implemented (Home,
//  Schedule, Social). Neutral stub — no content spikes.
//

import SwiftUI

struct ComingSoonView: View {
    @Environment(\.appTheme) private var theme

    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.dsDisplay(28))
                .foregroundStyle(theme.fg)
            Text(message)
                .font(.dsBody(14))
                .foregroundStyle(theme.fg2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
    }
}
