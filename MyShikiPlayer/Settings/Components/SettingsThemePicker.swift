//
//  SettingsThemePicker.swift
//  MyShikiPlayer
//
//  Theme radio buttons. Stores the selected id in @AppStorage("app.theme").
//  AppShellView reads the same key and recomputes the palette.
//

import SwiftUI

struct SettingsThemePicker: View {
    @Environment(\.appTheme) private var theme
    @AppStorage("app.theme") private var themeId: String = AppTheme.paper.id

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(AppTheme.all, id: \.id) { candidate in
                row(for: candidate)
            }
        }
    }

    private func row(for candidate: AppTheme) -> some View {
        let isSelected = themeId == candidate.id
        return Button {
            themeId = candidate.id
        } label: {
            HStack(spacing: 12) {
                swatch(for: candidate)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .font(.dsBody(13, weight: .medium))
                        .foregroundStyle(theme.fg)
                    Text(Self.subtitle(for: candidate))
                        .font(.dsMono(10))
                        .foregroundStyle(theme.fg3)
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(isSelected ? theme.accent : theme.line2, lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    if isSelected {
                        Circle()
                            .fill(theme.accent)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? theme.accent.opacity(0.07) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? theme.accent : theme.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func swatch(for candidate: AppTheme) -> some View {
        HStack(spacing: 0) {
            candidate.bg.frame(width: 16, height: 28)
            candidate.card.frame(width: 16, height: 28)
            candidate.accent.frame(width: 16, height: 28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
    }

    private static func subtitle(for candidate: AppTheme) -> String {
        switch candidate.id {
        case "paper":    return "Светлая, день"
        case "midnight": return "Тёмная, ночь"
        case "plum":     return "Неоновая"
        default:         return ""
        }
    }
}
