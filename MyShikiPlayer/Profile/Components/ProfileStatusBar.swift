//
//  ProfileStatusBar.swift
//  MyShikiPlayer
//
//  Horizontal stacked bar showing status proportions + a legend.
//  Statuses are mapped to Russian labels and colors.
//

import SwiftUI

struct ProfileStatusBar: View {
    @Environment(\.appTheme) private var theme
    let buckets: [UserStatBucket]

    private static let order: [String: (label: String, accent: AccentKey)] = [
        "watching":   ("Смотрю",      .accent),
        "completed":  ("Просмотрено", .good),
        "planned":    ("Запланировано", .violet),
        "on_hold":    ("Отложено",    .warn),
        "dropped":    ("Брошено",     .muted),
        "rewatching": ("Пересматриваю", .accent2)
    ]

    enum AccentKey { case accent, accent2, good, warn, violet, muted }

    private func color(for key: AccentKey) -> Color {
        switch key {
        case .accent:  return theme.accent
        case .accent2: return theme.accent2
        case .good:    return theme.good
        case .warn:    return theme.warn
        case .violet:  return theme.violet
        case .muted:   return theme.fg3
        }
    }

    struct NormalizedBucket: Identifiable {
        let key: String
        let label: String
        let count: Int
        let color: Color
        var id: String { key }
    }

    private var normalizedBuckets: [NormalizedBucket] {
        let total = buckets.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }
        return buckets.compactMap { bucket in
            guard let rawKey = Self.extractStatusKey(bucket), let meta = Self.order[rawKey] else { return nil }
            return NormalizedBucket(key: rawKey, label: meta.label, count: bucket.count, color: color(for: meta.accent))
        }
    }

    private static func extractStatusKey(_ bucket: UserStatBucket) -> String? {
        if let grouped = bucket.groupedId, let first = grouped.split(separator: ",").first {
            return String(first)
        }
        return bucket.name.map { $0.lowercased() }
    }

    var body: some View {
        let data = normalizedBuckets
        let total = data.reduce(0) { $0 + $1.count }
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(data) { row in
                        Rectangle()
                            .fill(row.color)
                            .frame(width: widthFor(count: row.count, total: total, full: geo.size.width))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())

            FlowLayout(spacing: 12, runSpacing: 8) {
                ForEach(data) { row in
                    HStack(spacing: 6) {
                        Circle().fill(row.color).frame(width: 7, height: 7)
                        Text(row.label)
                            .font(.dsBody(12, weight: .medium))
                            .foregroundStyle(theme.fg2)
                        Text("\(row.count)")
                            .font(.dsMono(11, weight: .semibold))
                            .foregroundStyle(theme.fg)
                    }
                }
            }
        }
    }

    private func widthFor(count: Int, total: Int, full: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return full * CGFloat(count) / CGFloat(total)
    }
}
