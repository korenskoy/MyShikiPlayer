//
//  DetailsSectionHeader.swift
//  MyShikiPlayer
//
//  Section header on the detail screen: large title + optional action string
//  on the right (plain text, not a button). If `isCollapsed` is passed —
//  only the right cluster (action + chevron) is the click target, with a
//  pointer cursor on hover; the title text stays selectable/non-interactive.
//

import AppKit
import SwiftUI

struct DetailsSectionHeader: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let action: String?
    let isCollapsed: Binding<Bool>?

    init(
        title: String,
        action: String?,
        isCollapsed: Binding<Bool>? = nil
    ) {
        self.title = title
        self.action = action
        self.isCollapsed = isCollapsed
    }

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            Text(title)
                .font(.dsTitle(22, weight: .bold))
                .foregroundStyle(theme.fg)
                .tracking(-0.3)
            Spacer(minLength: 12)
            rightCluster
        }
        .padding(.top, 32)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var rightCluster: some View {
        if let isCollapsed {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isCollapsed.wrappedValue.toggle()
                }
            } label: {
                rightClusterContent(showsChevron: true, collapsed: isCollapsed.wrappedValue)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        } else {
            rightClusterContent(showsChevron: false, collapsed: false)
        }
    }

    private func rightClusterContent(showsChevron: Bool, collapsed: Bool) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            if let action {
                Text(action)
                    .font(.dsBody(12, weight: .medium))
                    .foregroundStyle(theme.fg2)
            }
            if showsChevron {
                DSIcon(name: .chevD, size: 13, weight: .semibold)
                    .foregroundStyle(theme.fg3)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
            }
        }
    }
}
