//
//  ScoreDistributionCard.swift
//  MyShikiPlayer
//
//  Sidebar histogram of community scores 1…10 for the linked anime.
//  Bars are widthed against the largest bucket; alpha decays for lower
//  scores so the visual reads like the design's gradient.
//

import SwiftUI

struct ScoreDistributionCard: View {
    @Environment(\.appTheme) private var theme
    let stats: [AnimeScoresStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ОЦЕНКИ")
                .font(.dsLabel(9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(theme.accent)

            if let avg = averageScore {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.2f", avg))
                        .font(.dsTitle(28, weight: .heavy))
                        .foregroundStyle(theme.fg)
                    Text("из 10")
                        .font(.dsMono(11))
                        .foregroundStyle(theme.fg3)
                }
            }

            VStack(spacing: 4) {
                ForEach(rows, id: \.score) { row in
                    HStack(spacing: 8) {
                        Text("\(row.score)")
                            .font(.dsMono(10))
                            .frame(width: 16, alignment: .trailing)
                            .foregroundStyle(theme.fg3)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.bg2)
                                .frame(height: 8)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(theme.accent.opacity(barAlpha(for: row.score)))
                                    .frame(width: geo.size.width * row.fraction, height: 8)
                            }
                            .frame(height: 8)
                        }
                        Text(formatCount(row.count))
                            .font(.dsMono(10))
                            .frame(width: 56, alignment: .trailing)
                            .foregroundStyle(theme.fg3)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
    }

    private struct Row {
        let score: Int
        let count: Int
        let fraction: Double
    }

    private var rows: [Row] {
        guard !stats.isEmpty else { return [] }
        let maxCount = stats.map(\.count).max() ?? 1
        return (1...10).reversed().map { score in
            let count = stats.first { $0.score == score }?.count ?? 0
            let frac = maxCount > 0 ? Double(count) / Double(maxCount) : 0
            return Row(score: score, count: count, fraction: frac)
        }
    }

    private var averageScore: Double? {
        let total = stats.reduce(0) { $0 + $1.count }
        guard total > 0 else { return nil }
        let weighted = stats.reduce(0.0) { $0 + Double($1.score * $1.count) }
        return weighted / Double(total)
    }

    private func barAlpha(for score: Int) -> Double {
        switch score {
        case 9...10: return 1.0
        case 7...8:  return 0.85
        case 5...6:  return 0.65
        case 3...4:  return 0.45
        default:     return 0.30
        }
    }

    private func formatCount(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
