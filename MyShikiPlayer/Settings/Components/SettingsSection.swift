//
//  SettingsSection.swift
//  MyShikiPlayer
//
//  Standard settings section: title + description + content inside a card.
//

import SwiftUI

struct SettingsSection<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let description: String?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        description: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.description = description
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.dsTitle(16, weight: .semibold))
                    .foregroundStyle(theme.fg)
                if let description {
                    Text(description)
                        .font(.dsBody(12))
                        .foregroundStyle(theme.fg3)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(theme.line, lineWidth: 1)
            )
        }
    }
}
