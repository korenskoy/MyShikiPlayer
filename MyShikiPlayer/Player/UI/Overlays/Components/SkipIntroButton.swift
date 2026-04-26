//
//  SkipIntroButton.swift
//  MyShikiPlayer
//
//  Floating "Skip opening/ending" button. Appears when the current time is
//  inside the session's openingRangeSeconds. Kodik returns a single range —
//  either an intro or an ending; the label is derived from the position in
//  the video (see ClassicPlayerOverlay.skipLabel). The S shortcut is handled
//  in PlayerShortcuts.
//

import SwiftUI

struct SkipIntroButton: View {
    var label: String = "Пропустить опенинг"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                DSIcon(name: .skip, size: 15, weight: .semibold)
                Text(label)
                    .font(.dsBody(13, weight: .semibold))
                Text("S")
                    .font(.dsMono(10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
