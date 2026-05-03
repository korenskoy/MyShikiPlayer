//
//  ProfileStatCard.swift
//  MyShikiPlayer
//
//  KPI card in the stats row: large number + label + optional caption.
//

import SwiftUI

struct ProfileStatCard: View {
    @Environment(\.appTheme) private var theme
    let value: String
    let label: String
    let caption: String?

    init(value: String, label: String, caption: String? = nil) {
        self.value = value
        self.label = label
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.dsLabel(10, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(theme.fg3)
            Text(value)
                .font(.dsTitle(28, weight: .heavy))
                .tracking(-0.5)
                .foregroundStyle(theme.fg)
            if let caption {
                Text(caption)
                    .font(.dsMono(10))
                    .foregroundStyle(theme.fg3)
            }
            // Trailing flex space — lets cards in an HStack equalise to the
            // tallest sibling (only one carries a caption).
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
    }
}
