//
//  FilterSectionFrame.swift
//  MyShikiPlayer
//
//  Filter section chrome: uppercase mono header + content.
//  The header is clickable — the section collapses/expands, the chevron
//  rotates, and state persists across sessions (@AppStorage keyed by title).
//

import SwiftUI

struct FilterSectionFrame<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let content: Content
    @AppStorage private var isExpanded: Bool

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self._isExpanded = AppStorage(wrappedValue: true, "filter.section.\(title).expanded")
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center) {
                    Text(title)
                        .dsMonoLabel(size: 10, tracking: 1.5)
                        .foregroundStyle(theme.fg2)
                    Spacer()
                    DSIcon(name: .chevD, size: 12, weight: .regular)
                        .foregroundStyle(theme.fg3)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
