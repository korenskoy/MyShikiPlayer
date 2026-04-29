//
//  RailListsBlock.swift
//  MyShikiPlayer
//
//  Sidebar block summarising how users sorted the linked anime across their
//  lists (watching / completed / planned / on hold / dropped). Each row is
//  a coloured dot + russian label + grouped-thousand count.
//

import SwiftUI

struct RailListsBlock: View {
    @Environment(\.appTheme) private var theme
    let stats: [AnimeStatusesStat]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("СПИСКИ")
                .font(.dsLabel(9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(theme.accent)

            VStack(spacing: 6) {
                ForEach(orderedRows, id: \.status) { row in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(color(for: row.status))
                            .frame(width: 8, height: 8)
                        Text(label(for: row.status))
                            .font(.dsBody(12))
                            .foregroundStyle(theme.fg2)
                            .lineLimit(1)
                            .frame(width: 110, alignment: .leading)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.bg2)
                                .frame(height: 6)
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(color(for: row.status).opacity(0.85))
                                    .frame(
                                        width: geo.size.width * fraction(row.count),
                                        height: 6
                                    )
                            }
                            .frame(height: 6)
                        }
                        Text(formatCount(row.count))
                            .font(.dsMono(11))
                            .foregroundStyle(theme.fg3)
                            .frame(width: 56, alignment: .trailing)
                            .lineLimit(1)
                    }
                }
            }

            if total > 0 {
                Text("всего: \(formatCount(total))")
                    .font(.dsMono(10))
                    .foregroundStyle(theme.fg3)
                    .padding(.top, 2)
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

    private struct Row { let status: String; let count: Int }

    private var orderedRows: [Row] {
        let order = ["completed", "watching", "planned", "on_hold", "dropped", "rewatching"]
        var byStatus: [String: Int] = [:]
        for s in stats { byStatus[s.status] = (byStatus[s.status] ?? 0) + s.count }
        var rows: [Row] = []
        for s in order {
            if let count = byStatus.removeValue(forKey: s), count > 0 {
                rows.append(Row(status: s, count: count))
            }
        }
        for (status, count) in byStatus where count > 0 {
            rows.append(Row(status: status, count: count))
        }
        return rows
    }

    private var total: Int { stats.reduce(0) { $0 + $1.count } }

    /// Bar width is normalised against the largest bucket so even tiny rows
    /// (e.g. "rewatching") stay visible. Falls back to 0 when there is no
    /// data, which collapses the bar to invisible.
    private func fraction(_ count: Int) -> Double {
        let maxCount = stats.map(\.count).max() ?? 0
        guard maxCount > 0 else { return 0 }
        return Double(count) / Double(maxCount)
    }

    private func formatCount(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func label(for status: String) -> String {
        switch status {
        case "watching":   return "Смотрят"
        case "completed":  return "Просмотрено"
        case "planned":    return "Запланировано"
        case "on_hold":    return "Отложено"
        case "dropped":    return "Брошено"
        case "rewatching": return "Пересматривают"
        default:           return status
        }
    }

    private func color(for status: String) -> Color {
        switch status {
        case "completed":  return theme.good
        case "watching":   return theme.accent
        case "planned":    return theme.fg2
        case "on_hold":    return theme.warn
        case "dropped":    return theme.fg3
        case "rewatching": return theme.violet
        default:           return theme.fg3
        }
    }
}
