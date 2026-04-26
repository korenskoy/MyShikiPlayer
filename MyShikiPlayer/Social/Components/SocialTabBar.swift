//
//  SocialTabBar.swift
//  MyShikiPlayer
//
//  Tab switcher "Friends / Discussions" for the Social page.
//  Style — mini chips with the active one underlined.
//

import SwiftUI

struct SocialTabBar: View {
    @Environment(\.appTheme) private var theme
    @Binding var selected: SocialTab

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SocialTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer()
        }
    }

    private func tabButton(_ tab: SocialTab) -> some View {
        let isActive = selected == tab
        return Button {
            selected = tab
        } label: {
            VStack(alignment: .center, spacing: 6) {
                Text(tab.title)
                    .font(.dsBody(13, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? theme.fg : theme.fg3)
                Rectangle()
                    .fill(isActive ? theme.accent : Color.clear)
                    .frame(height: 2)
            }
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
