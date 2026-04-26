//
//  HUDComponents.swift
//  MyShikiPlayer
//

import SwiftUI

struct HUDPanel<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(HUDTheme.panelPadding)
            .background(HUDTheme.panelBackground(colorScheme: colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HUDTheme.cornerRadius, style: .continuous)
                    .stroke(HUDTheme.borderColor(colorScheme: colorScheme), lineWidth: 1)
            }
    }
}

struct HUDChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, HUDTheme.chipHorizontalPadding)
                .padding(.vertical, HUDTheme.chipVerticalPadding)
                .background(selected ? HUDTheme.selectedChipBackground(.accentColor) : HUDTheme.unselectedChipBackground(colorScheme: colorScheme))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
