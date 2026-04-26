//
//  CenterPlayButton.swift
//  MyShikiPlayer
//
//  Central round play indicator (shown when paused).
//  Tapping anywhere on the overlay already toggles play/pause — this button is
//  just a visual anchor; allowsHitTesting(false) keeps it from intercepting clicks.
//

import SwiftUI

struct CenterPlayButton: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.12))
                .background(.ultraThinMaterial, in: Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                )
            DSIcon(name: .play, size: 26, weight: .semibold)
                .foregroundStyle(Color.white)
                .offset(x: 2) // visually balance the triangle
        }
        .frame(width: 72, height: 72)
        .allowsHitTesting(false)
    }
}
