//
//  NextEpisodeCard.swift
//  MyShikiPlayer
//
//  Floating "Next episode N" card with a countdown and a jump button.
//  Shown when the remaining time is below the threshold seconds.
//  No thumbnail or title — that data is not available yet.
//

import SwiftUI

struct NextEpisodeCard: View {
    let nextEpisodeNumber: Int
    let remainingSeconds: Double
    let accent: Color
    let onPlayNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ДАЛЕЕ")
                .dsMonoLabel(size: 9, tracking: 1)
                .foregroundStyle(Color.white.opacity(0.55))

            Text("Следующий эпизод \(nextEpisodeNumber)")
                .font(.dsBody(13, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)

            HStack(spacing: 10) {
                Button(action: onPlayNext) {
                    HStack(spacing: 6) {
                        DSIcon(name: .play, size: 11, weight: .bold)
                        Text("Далее")
                            .font(.dsBody(11, weight: .bold))
                    }
                    .foregroundStyle(Color(hex: 0x0B0A0D))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(accent)
                    )
                }
                .buttonStyle(.plain)

                Text("через \(PlayerTimeFormatter.mmss(max(0, remainingSeconds)))")
                    .font(.dsMono(10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
            .padding(.top, 4)
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: 0x141218).opacity(0.85))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}
