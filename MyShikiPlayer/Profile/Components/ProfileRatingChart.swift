//
//  ProfileRatingChart.swift
//  MyShikiPlayer
//
//  Bar histogram of scores 1-10. Each bar has a label below and the
//  exact rating count above.
//

import SwiftUI

struct ProfileRatingChart: View {
    @Environment(\.appTheme) private var theme
    /// Index 0 = "1 star", index 9 = "10 stars".
    let bins: [Int]
    /// Average score (nil when bins is empty).
    let average: Double?

    private var maxBin: Int { max(bins.max() ?? 1, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(bins.enumerated()), id: \.offset) { idx, count in
                    column(value: count, index: idx + 1)
                }
            }
            .frame(height: 120)

            if let average {
                HStack {
                    Text("Средняя оценка")
                        .font(.dsMono(11))
                        .foregroundStyle(theme.fg3)
                    Spacer()
                    Text(String(format: "%.2f", average))
                        .font(.dsTitle(14, weight: .bold))
                        .foregroundStyle(theme.fg)
                }
            }
        }
    }

    private func column(value: Int, index: Int) -> some View {
        VStack(spacing: 4) {
            Text(value > 0 ? "\(value)" : " ")
                .font(.dsMono(9))
                .foregroundStyle(theme.fg3)
                .frame(height: 12)
            GeometryReader { geo in
                VStack {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(colorFor(index: index))
                        .frame(height: heightFor(value: value, maxAvailable: geo.size.height))
                }
            }
            .frame(maxWidth: .infinity)
            Text("\(index)")
                .font(.dsMono(10, weight: .semibold))
                .foregroundStyle(index >= 8 ? theme.accent : theme.fg3)
                .frame(height: 14)
        }
    }

    private func heightFor(value: Int, maxAvailable: CGFloat) -> CGFloat {
        guard maxBin > 0, maxAvailable > 0 else { return 0 }
        let ratio = CGFloat(value) / CGFloat(maxBin)
        return max(2, maxAvailable * ratio)
    }

    /// 1-4 — muted fg3, 5-7 — muted accent, 8-10 — full accent.
    private func colorFor(index: Int) -> Color {
        switch index {
        case 8...10: return theme.accent
        case 5...7:  return theme.accent.opacity(0.6)
        default:     return theme.fg3.opacity(0.45)
        }
    }
}
