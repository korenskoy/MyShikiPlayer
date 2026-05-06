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

    private struct Row { let status: String; let count: Int; let fraction: Double; let formattedCount: String }

    /// Precomputed table — built once per `init`, so the rows don't re-walk
    /// the stats / re-allocate `NumberFormatter` on every theme tick.
    private let orderedRows: [Row]
    private let total: Int
    private let formattedTotal: String

    init(stats: [AnimeStatusesStat]) {
        self.stats = stats
        let computed = Self.compute(stats: stats)
        self.orderedRows = computed.rows
        self.total = computed.total
        self.formattedTotal = computed.formattedTotal
    }

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
                                        width: geo.size.width * row.fraction,
                                        height: 6
                                    )
                            }
                            .frame(height: 6)
                        }
                        Text(row.formattedCount)
                            .font(.dsMono(11))
                            .foregroundStyle(theme.fg3)
                            .frame(width: 56, alignment: .trailing)
                            .lineLimit(1)
                    }
                }
            }

            if total > 0 {
                Text("всего: \(formattedTotal)")
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

    /// Single static `NumberFormatter` — building one on every render is
    /// surprisingly expensive in aggregate, since the sidebar updates with
    /// every parent re-render of the topic detail view.
    private static let countFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        return f
    }()

    private static func formatCount(_ n: Int) -> String {
        countFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private static func compute(
        stats: [AnimeStatusesStat]
    ) -> (rows: [Row], total: Int, formattedTotal: String) {
        let order = ["completed", "watching", "planned", "on_hold", "dropped", "rewatching"]
        var byStatus: [String: Int] = [:]
        for s in stats { byStatus[s.status] = (byStatus[s.status] ?? 0) + s.count }

        var ordered: [(status: String, count: Int)] = []
        for s in order {
            if let count = byStatus.removeValue(forKey: s), count > 0 {
                ordered.append((s, count))
            }
        }
        for (status, count) in byStatus where count > 0 {
            ordered.append((status, count))
        }

        let total = ordered.reduce(0) { $0 + $1.count }
        let maxCount = ordered.map(\.count).max() ?? 0
        let rows: [Row] = ordered.map { entry in
            // Bar width is normalised against the largest bucket so even tiny
            // rows stay visible.
            let fraction = maxCount > 0 ? Double(entry.count) / Double(maxCount) : 0
            return Row(
                status: entry.status,
                count: entry.count,
                fraction: fraction,
                formattedCount: formatCount(entry.count)
            )
        }
        return (rows, total, formatCount(total))
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
