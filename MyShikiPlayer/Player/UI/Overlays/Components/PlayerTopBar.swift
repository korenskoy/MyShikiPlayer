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
    let isAlwaysOnTop: Bool
    let onBack: () -> Void
    let onToggleAlwaysOnTop: () -> Void

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

            // Right-side action: keep player window always on top.
            // Width matches the left "Back" button block so the heading
            // stays visually centered.
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                Button(action: onToggleAlwaysOnTop) {
                    DSIcon(
                        name: isAlwaysOnTop ? .pinFill : .pin,
                        size: 14,
                        weight: .semibold
                    )
                    .foregroundStyle(Color.white.opacity(isAlwaysOnTop ? 1.0 : 0.7))
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isAlwaysOnTop ? Color.white.opacity(0.18) : Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .animation(.easeInOut(duration: 0.15), value: isAlwaysOnTop)
                }
                .buttonStyle(.plain)
                .help(isAlwaysOnTop ? "Поверх других окон: вкл" : "Поверх других окон: выкл")
            }
            .frame(width: 120)
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
