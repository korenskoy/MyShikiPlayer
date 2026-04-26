//
//  CatalogFilterCheckboxRow.swift
//  MyShikiPlayer
//
//  Checkbox row in catalog filters: square + label + optional count.
//  Equivalent of Checkbox from screens-catalog.jsx.
//

import SwiftUI

struct CatalogFilterCheckboxRow: View {
    @Environment(\.appTheme) private var theme
    let label: String
    let count: Int?
    let isChecked: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 8) {
                checkbox
                Text(label)
                    .font(.dsBody(13))
                    .foregroundStyle(theme.fg2)
                Spacer()
                if let count {
                    Text("\(count)")
                        .font(.dsMono(10))
                        .foregroundStyle(theme.fg3)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var checkbox: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .strokeBorder(isChecked ? theme.accent : theme.line2, lineWidth: isChecked ? 0 : 1)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(isChecked ? theme.accent : Color.clear)
            )
            .frame(width: 14, height: 14)
            .overlay {
                if isChecked {
                    DSIcon(name: .check, size: 9, weight: .black)
                        .foregroundStyle(theme.mode == .dark ? Color(hex: 0x0B0A0D) : Color.white)
                }
            }
    }
}
