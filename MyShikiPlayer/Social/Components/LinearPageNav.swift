//
//  LinearPageNav.swift
//  MyShikiPlayer
//
//  Decorative page navigator placed above and below the flat-thread post
//  list. The numbered chips and "след. →" label are visual only — actual
//  pagination is driven by the "Загрузить ещё N из M" control inside the
//  list, mirroring how Shikimori's web client paginates discussion threads.
//  This component only reflects the current "P/T" position and how many
//  comments are loaded against the topic total.
//

import SwiftUI

struct LinearPageNav: View {
    @Environment(\.appTheme) private var theme

    /// 1-based "current" page within the thread, where page 1 is the very
    /// oldest and `totalPages` is the newest. Because the UI shows comments
    /// in ascending order with the newest batch at the bottom, the caller
    /// computes this as `totalPages - loadedPages + 1`.
    let currentPage: Int
    let totalPages: Int
    /// How many comments are currently rendered (across all loaded pages).
    let loaded: Int
    /// Total comments reported by the topic.
    let total: Int

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("СТРАНИЦА:")
                .tracking(1)
                .foregroundStyle(theme.fg3)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                chip(for: item)
            }
            Spacer(minLength: 8)
            Text(statsText)
                .foregroundStyle(theme.fg3)
        }
        .font(.dsMono(11))
        // Active chip carries vertical padding (3pt × 2) → ~22pt tall.
        // Pinning the row height keeps the right-side stats text centred
        // against the chips instead of floating above them.
        .frame(minHeight: 22)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
    }

    // MARK: - Page items

    enum PageItem: Hashable {
        case number(Int)
        case ellipsis
    }

    private var items: [PageItem] {
        Self.pageItems(currentPage: currentPage, totalPages: totalPages)
    }

    /// Page-window pager: short threads list every page; longer ones keep
    /// the first / last pages pinned and show a `current ± 1` window in the
    /// middle so the highlighted "you are here" chip is always visible. A
    /// gap of one is filled with the missing page rather than an ellipsis
    /// (`[1, 2, 3, …]` instead of `[1, …, 3, …]`) to keep the layout calm.
    /// Static + pure so it can be exercised directly from unit tests without
    /// instantiating the SwiftUI view.
    static func pageItems(currentPage: Int, totalPages: Int) -> [PageItem] {
        guard totalPages > 1 else { return [] }
        if totalPages <= 7 {
            return (1...totalPages).map { .number($0) }
        }
        let cur = max(1, min(currentPage, totalPages))
        let lo = max(2, cur - 1)
        let hi = min(totalPages - 1, cur + 1)

        var items: [PageItem] = [.number(1)]
        if lo == 3 {
            items.append(.number(2))
        } else if lo > 3 {
            items.append(.ellipsis)
        }
        for n in lo...hi { items.append(.number(n)) }
        if hi == totalPages - 2 {
            items.append(.number(totalPages - 1))
        } else if hi < totalPages - 2 {
            items.append(.ellipsis)
        }
        items.append(.number(totalPages))
        return items
    }

    @ViewBuilder
    private func chip(for item: PageItem) -> some View {
        switch item {
        case .number(let n):
            let isCurrent = n == currentPage
            Text("\(n)")
                .fontWeight(isCurrent ? .heavy : .medium)
                .foregroundStyle(isCurrent ? activeTextColor : theme.fg2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isCurrent ? theme.accent : .clear)
                )
        case .ellipsis:
            Text("…")
                .foregroundStyle(theme.fg3)
        }
    }

    /// In dark themes the accent is bright (red / cyan) and reads best with
    /// black text per the design tokens; in light themes accent is a deep
    /// red and white sits on top.
    private var activeTextColor: Color {
        theme.mode == .dark ? .black : .white
    }

    private var statsText: String {
        if totalPages <= 0 {
            return "\(loaded) из \(max(loaded, total))"
        }
        let p = max(1, min(currentPage, totalPages))
        return "\(loaded) из \(total) · стр. \(p)/\(totalPages)"
    }
}
