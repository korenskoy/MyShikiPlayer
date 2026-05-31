//
//  CatalogSortChips.swift
//  MyShikiPlayer
//
//  Reusable sort-by row that both Catalog and Library headers render.
//  Behavior:
//    • Click an inactive chip → it becomes the active order, direction
//      resets to descending (the natural order for ranked/aired_on/score).
//    • Click the already-active chip → flip ascending/descending.
//    • Clearing the order (back to nil) is the responsibility of the
//      filter sidebar — the chip row never sets `order = nil` on its own.
//

import SwiftUI

struct CatalogSortChips: View {
    @Environment(\.appTheme) private var theme

    @Binding var order: AnimeOrder?
    @Binding var ascending: Bool
    let options: [AnimeOrder]

    var body: some View {
        HStack(spacing: 8) {
            Text("Сортировка:")
                .font(.dsBody(12))
                .foregroundStyle(theme.fg2)

            ForEach(options, id: \.self) { opt in
                DSChip(
                    title: label(for: opt),
                    isActive: order == opt,
                    size: .small,
                    mono: true,
                    action: { handleTap(opt) }
                )
            }
        }
    }

    private func label(for opt: AnimeOrder) -> String {
        let base = displayName(opt)
        guard order == opt else { return base }
        return "\(base) \(ascending ? "↑" : "↓")"
    }

    private func displayName(_ opt: AnimeOrder) -> String {
        switch opt {
        case .ranked:     return "по рейтингу"
        case .airedOn:    return "по году"
        case .popularity: return "по популярности"
        default:          return opt.displayName.lowercased()
        }
    }

    private func handleTap(_ opt: AnimeOrder) {
        if order == opt {
            ascending.toggle()
        } else {
            order = opt
            ascending = false
        }
    }
}
