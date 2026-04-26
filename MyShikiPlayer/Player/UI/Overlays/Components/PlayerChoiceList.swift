//
//  PlayerChoiceList.swift
//  MyShikiPlayer
//
//  Generic popover content for picking a single value.
//  Used by the DUB / quality / speed pills in PlayerBottomBar.
//  The theme is always dark (player), so colors are hardcoded as constants.
//

import SwiftUI

struct PlayerChoiceList<Item: Hashable>: View {
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
                    .foregroundStyle(Color.white.opacity(0.5))
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
                .padding(.bottom, 6)
                .padding(.top, header == nil ? 6 : 0)
            }
        }
        .frame(minWidth: 220, maxHeight: 360)
        .background(Color(hex: 0x141218))
    }

    private func row(for item: Item) -> some View {
        let selected = isSelected(item)
        return Button(action: { onSelect(item) }) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleFor(item))
                        .font(.dsBody(12, weight: selected ? .semibold : .medium))
                        .foregroundStyle(Color.white)
                    if let sub = subtitleFor?(item), !sub.isEmpty {
                        Text(sub)
                            .font(.dsMono(9, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                Spacer()
                if selected {
                    DSIcon(name: .check, size: 12, weight: .bold)
                        .foregroundStyle(Color(hex: 0xFF4D5E))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
