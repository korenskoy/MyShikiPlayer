//
//  OngoingsView.swift
//  MyShikiPlayer
//
//  Ongoings branch: the airing calendar and the rating-ordered release
//  grid, switched by a tab bar. The selected tab lives in NavigationState
//  so returning to the branch restores it.
//

import SwiftUI

struct OngoingsView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var auth: ShikimoriAuthController
    @Binding var tab: NavigationState.OngoingsTab

    let onOpenDetails: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            tabBar

            switch tab {
            case .calendar:
                ScheduleView(auth: auth, onOpenDetails: onOpenDetails)
            case .releases:
                OngoingReleasesView(auth: auth, onOpenDetails: onOpenDetails)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.bg)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(NavigationState.OngoingsTab.allCases) { item in
                tabButton(item)
            }
            Spacer()
        }
        .padding(.horizontal, 34)
        .padding(.top, 14)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.line)
                .frame(height: 1)
        }
    }

    private func tabButton(_ item: NavigationState.OngoingsTab) -> some View {
        let isActive = tab == item
        return Button {
            tab = item
        } label: {
            VStack(alignment: .center, spacing: 6) {
                Text(item.title)
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
