//
//  DetailsChoiceList.swift
//  MyShikiPlayer
//
//  Paper-themed choice list for popovers on the details screen
//  (watching status / dub). Analogous to PlayerChoiceList but in the light
//  theme and with a larger hit-area.
//

import SwiftUI

struct DetailsChoiceList<Item: Hashable>: View {
    @Environment(\.appTheme) private var theme
    let header: String?
    let items: [Item]
    let titleFor: (Item) -> String
    var subtitleFor: ((Item) -> String?)? = nil
    let isSelected: (Item) -> Bool
    let onSelect: (Item) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                Text(header)
                    .dsMonoLabel(size: 10, tracking: 1.4)
                    .foregroundStyle(theme.fg3)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(items, id: \.self) { item in
                        row(for: item)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
                .padding(.top, header == nil ? 8 : 0)
            }
        }
        .frame(minWidth: 240, maxHeight: 360)
        .background(theme.card)
    }

    private func row(for item: Item) -> some View {
        let selected = isSelected(item)
        return Button(action: { onSelect(item) }) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleFor(item))
                        .font(.dsBody(13, weight: selected ? .semibold : .medium))
                        .foregroundStyle(theme.fg)
                    if let sub = subtitleFor?(item), !sub.isEmpty {
                        Text(sub)
                            .font(.dsMono(10))
                            .foregroundStyle(theme.fg3)
                    }
                }
                Spacer()
                if selected {
                    DSIcon(name: .check, size: 13, weight: .bold)
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? theme.chipBg : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
