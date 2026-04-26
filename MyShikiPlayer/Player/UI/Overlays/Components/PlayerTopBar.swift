//
//  PlayerTopBar.swift
//  MyShikiPlayer
//
//  Top player bar (variant A): "Back" on the left, compact heading
//  (mono label "ЭП NN" + title) in the center. The background is a black
//  gradient for readability over the video.
//

import SwiftUI

struct PlayerTopBar: View {
    let episodeNumber: Int
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    DSIcon(name: .chevL, size: 14, weight: .semibold)
                    Text("Назад к аниме")
                        .font(.dsBody(12, weight: .semibold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Закрыть плеер (Esc)")

            VStack(spacing: 2) {
                Text(title)
                    .font(.dsTitle(15))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text("ЭП \(String(format: "%02d", episodeNumber))")
                    .dsMonoLabel(size: 10, tracking: 1.5)
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity)

            // Symmetric spacer block so the heading is visually centered
            // relative to the "Back" button on the left. Invisible and non-interactive.
            HStack(spacing: 6) {
                Color.clear.frame(width: 120, height: 1)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.65), Color.black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        )
    }
}
