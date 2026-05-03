//
//  CatalogHeader.swift
//  MyShikiPlayer
//
//  Catalog header: kicker "КАТАЛОГ · KATALOG", title with count,
//  sort chips on the right + variant toggle. Below — the row of
//  active filters.
//

import SwiftUI

struct CatalogHeader: View {
    @Environment(\.appTheme) private var theme

    let totalCount: Int
    @Binding var order: AnimeOrder?
    @Binding var variant: CatalogVariant
    let activeFacetLabels: [String]
    let onResetFilters: () -> Void

    private let orderOptions: [AnimeOrder] = [.ranked, .airedOn, .popularity]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            topRow
            activeFiltersRow
        }
    }

    private var topRow: some View {
        HStack(alignment: .bottom, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Весь каталог")
                    .font(.dsDisplay(28, weight: .bold))
                    .foregroundStyle(theme.fg)
                    .tracking(-0.5)
                Text("· \(totalCount)")
                    .font(.dsTitle(24, weight: .regular))
                    .foregroundStyle(theme.fg3)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Text("Сортировка:")
                    .font(.dsBody(12))
                    .foregroundStyle(theme.fg2)

                ForEach(orderOptions, id: \.self) { opt in
                    DSChip(
                        title: orderLabel(opt),
                        isActive: order == opt,
                        size: .small,
                        mono: true,
                        action: {
                            order = (order == opt) ? nil : opt
                        }
                    )
                }

                Rectangle()
                    .fill(theme.line)
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 4)

                CatalogVariantToggle(selection: $variant)
            }
        }
    }

    @ViewBuilder
    private var activeFiltersRow: some View {
        HStack(alignment: .center, spacing: 6) {
            Text("АКТИВНО:")
                .font(.dsLabel(10))
                .tracking(1.4)
                .foregroundStyle(theme.fg3)

            if activeFacetLabels.isEmpty {
                Text("фильтров не применено")
                    .font(.dsBody(11))
                    .foregroundStyle(theme.fg3)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(activeFacetLabels, id: \.self) { label in
                        activeChip(label)
                    }
                    clearAllButton
                }
            }
            Spacer()
        }
    }

    private func activeChip(_ label: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.dsBody(11, weight: .semibold))
            DSIcon(name: .xmark, size: 10, weight: .bold)
        }
        .foregroundStyle(theme.mode == .dark ? Color(hex: 0x0B0A0D) : Color.white)
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(theme.accent)
        )
    }

    private var clearAllButton: some View {
        Button(action: onResetFilters) {
            Text("очистить всё")
                .font(.dsLabel(10))
                .tracking(1.2)
                .foregroundStyle(theme.fg3)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func orderLabel(_ order: AnimeOrder) -> String {
        switch order {
        case .ranked:     return "по рейтингу ↓"
        case .airedOn:    return "по году"
        case .popularity: return "по популярности"
        default:          return order.displayName.lowercased()
        }
    }
}
