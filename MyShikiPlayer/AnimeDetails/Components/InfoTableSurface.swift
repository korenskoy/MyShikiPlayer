//
//  InfoTableSurface.swift
//  MyShikiPlayer
//
//  Right column: key-value table about the title.
//

import SwiftUI

struct InfoTableSurface: View {
    @Environment(\.appTheme) private var theme
    let detail: AnimeDetail

    var body: some View {
        DSSurface(padding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                Text("О ТАЙТЛЕ")
                    .dsMonoLabel(size: 10, tracking: 1.5)
                    .foregroundStyle(theme.fg3)
                    .padding(.bottom, 10)

                ForEach(rows, id: \.key) { row in
                    HStack(alignment: .top) {
                        Text(row.key)
                            .font(.dsBody(12))
                            .foregroundStyle(theme.fg3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.value)
                            .font(.dsBody(12, weight: .medium))
                            .foregroundStyle(theme.fg)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) {
                        if row.key != rows.last?.key {
                            Rectangle()
                                .fill(theme.line)
                                .frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private struct Row: Hashable { let key: String; let value: String }

    private var rows: [Row] {
        var out: [Row] = []
        if let kind = detail.kind?.uppercased(), !kind.isEmpty {
            out.append(Row(key: "Тип", value: kind))
        }
        if let status = detail.status, !status.isEmpty {
            out.append(Row(key: "Статус", value: statusLabel(status)))
        }
        if let airedOn = detail.airedOn {
            out.append(Row(key: "Вышло", value: airedOn))
        }
        if let duration = detail.duration, duration > 0 {
            out.append(Row(key: "Длительность эп.", value: "\(duration) мин"))
        }
        if let rating = detail.rating, !rating.isEmpty {
            out.append(Row(key: "Возрастной рейтинг", value: ratingLabel(rating)))
        }
        if let studios = detail.studios?.compactMap(\.name), !studios.isEmpty {
            out.append(Row(key: "Студия", value: studios.joined(separator: ", ")))
        }
        if let licensors = detail.licensors, !licensors.isEmpty {
            out.append(Row(key: "Лицензиар", value: licensors.joined(separator: ", ")))
        }
        if let franchise = detail.franchise, !franchise.isEmpty {
            out.append(Row(key: "Франшиза", value: franchise))
        }
        if let mal = detail.myanimelistId {
            out.append(Row(key: "MAL", value: "#\(mal)"))
        }
        return out
    }

    private func statusLabel(_ raw: String) -> String {
        switch raw {
        case "ongoing":  return "Онгоинг"
        case "released": return "Вышло"
        case "anons":    return "Анонс"
        case "latest":   return "Недавно"
        default:         return raw.capitalized
        }
    }

    private func ratingLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "g":       return "G"
        case "pg":      return "PG"
        case "pg_13":   return "PG-13"
        case "r":       return "R-17"
        case "r_plus":  return "R+"
        case "rx":      return "Rx"
        default:        return raw.uppercased()
        }
    }
}
