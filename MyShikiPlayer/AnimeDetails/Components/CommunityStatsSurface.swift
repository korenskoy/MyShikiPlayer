//
//  CommunityStatsSurface.swift
//  MyShikiPlayer
//
//  Community score histogram (10->5) from GraphQL scoresStats.
//  Plus a "lists" breakdown by status.
//

import SwiftUI

struct CommunityStatsSurface: View {
    @Environment(\.appTheme) private var theme
    let stats: GraphQLAnimeStatsEntry

    private var scoresSorted: [(score: Int, count: Int)] {
        (stats.scoresStats ?? [])
            .map { ($0.score, $0.count) }
            .sorted { $0.score > $1.score }
    }

    private var totalScores: Int {
        scoresSorted.reduce(0) { $0 + $1.count }
    }

    private var statuses: [(status: String, count: Int)] {
        (stats.statusesStats ?? [])
            .map { ($0.status, $0.count) }
    }

    private var totalStatuses: Int {
        statuses.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        if scoresSorted.isEmpty && statuses.isEmpty {
            EmptyView()
        } else {
            DSSurface(padding: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    if !scoresSorted.isEmpty {
                        scoresBlock
                    }
                    if !statuses.isEmpty {
                        if !scoresSorted.isEmpty {
                            Rectangle()
                                .fill(theme.line)
                                .frame(height: 1)
                        }
                        statusesBlock
                    }
                }
            }
        }
    }

    private var scoresBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ОЦЕНКИ СООБЩЕСТВА")
                .dsMonoLabel(size: 10, tracking: 1.5)
                .foregroundStyle(theme.fg3)

            ForEach(scoresSorted, id: \.score) { entry in
                scoreRow(score: entry.score, count: entry.count)
            }

            Text("Всего \(totalScores) оценок")
                .font(.dsMono(10))
                .foregroundStyle(theme.fg3)
                .padding(.top, 4)
        }
    }

    private func scoreRow(score: Int, count: Int) -> some View {
        let fraction = totalScores > 0 ? Double(count) / Double(totalScores) : 0
        let percent = Int((fraction * 100).rounded())
        return HStack(spacing: 8) {
            Text("\(score)")
                .font(.dsMono(10, weight: .semibold))
                .foregroundStyle(theme.fg2)
                .frame(width: 14, alignment: .leading)

            DSProgressBar(value: fraction, height: 5)

            Text("\(percent)%")
                .font(.dsMono(10))
                .foregroundStyle(theme.fg3)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private var statusesBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("В СПИСКАХ")
                .dsMonoLabel(size: 10, tracking: 1.5)
                .foregroundStyle(theme.fg3)

            ForEach(statuses, id: \.status) { entry in
                statusRow(entry.status, count: entry.count)
            }

            Text("Всего \(formatCount(totalStatuses)) пользователей")
                .font(.dsMono(10))
                .foregroundStyle(theme.fg3)
                .padding(.top, 4)
        }
    }

    private func statusRow(_ status: String, count: Int) -> some View {
        let fraction = totalStatuses > 0 ? Double(count) / Double(totalStatuses) : 0
        return HStack(spacing: 8) {
            Text(statusLabel(status))
                .font(.dsBody(12))
                .foregroundStyle(theme.fg2)
                .frame(width: 110, alignment: .leading)

            DSProgressBar(value: fraction, height: 5)

            Text(formatCount(count))
                .font(.dsMono(10, weight: .medium))
                .foregroundStyle(theme.fg)
                .frame(width: 50, alignment: .trailing)
        }
    }

    private func statusLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "watching":   return "Смотрят"
        case "planned":    return "В планах"
        case "completed":  return "Просмотрели"
        case "rewatching": return "Пересматривают"
        case "on_hold":    return "Отложили"
        case "dropped":    return "Бросили"
        default:           return raw.capitalized
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000)
        }
        return "\(count)"
    }
}
