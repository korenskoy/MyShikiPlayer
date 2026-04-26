//
//  LibraryStatusTabs.swift
//  MyShikiPlayer
//
//  Horizontal tab bar in Shikimori style: "All · N / Watching · N / …".
//  Active tab uses an accent fill.
//

import SwiftUI

struct LibraryStatusTabs: View {
    @Environment(\.appTheme) private var theme
    @Binding var selected: AnimeListViewModel.StatusTab
    let counts: (AnimeListViewModel.StatusTab) -> Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AnimeListViewModel.StatusTab.allCases, id: \.rawValue) { tab in
                    tabButton(tab)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func tabButton(_ tab: AnimeListViewModel.StatusTab) -> some View {
        let count = counts(tab)
        let isActive = selected == tab
        return Button {
            selected = tab
        } label: {
            HStack(spacing: 6) {
                Text(tab.title)
                    .font(.dsBody(13, weight: isActive ? .semibold : .medium))
                Text("\(count)")
                    .font(.dsMono(11, weight: .semibold))
                    .foregroundStyle(isActive ? activeForeground.opacity(0.7) : theme.fg3)
            }
            .foregroundStyle(isActive ? activeForeground : theme.fg2)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? theme.accent : theme.chipBg)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isActive ? theme.accent : theme.chipBr, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var activeForeground: Color {
        theme.mode == .dark ? Color(hex: 0x0B0A0D) : .white
    }
}
