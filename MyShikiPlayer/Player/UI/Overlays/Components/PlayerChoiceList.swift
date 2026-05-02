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
        PlayerChoiceRow(
            title: titleFor(item),
            subtitle: subtitleFor?(item),
            isSelected: isSelected(item),
            onSelect: { onSelect(item) }
        )
    }
}
