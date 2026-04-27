//
//  SettingsSection.swift
//  MyShikiPlayer
//
//  Standard settings section: title + description + content inside a card.
//  Optional collapsible mode exposes a chevron in the header and hides the
//  card body until the user expands it. The description stays visible when
//  collapsed so the section still explains itself at a glance.
//

import SwiftUI

struct SettingsSection<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let description: String?
    @Binding private var isCollapsed: Bool
    private let isCollapsible: Bool
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        description: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.description = description
        self._isCollapsed = .constant(false)
        self.isCollapsible = false
        self.content = content
    }

    init(
        title: String,
        description: String? = nil,
        isCollapsed: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.description = description
        self._isCollapsed = isCollapsed
        self.isCollapsible = true
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if !isCollapsible || !isCollapsed {
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

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if isCollapsible {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.dsTitle(16, weight: .semibold))
                            .foregroundStyle(theme.fg)
                        if let description {
                            Text(description)
                                .font(.dsBody(12))
                                .foregroundStyle(theme.fg3)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    DSIcon(
                        name: isCollapsed ? .chevD : .chevU,
                        size: 11,
                        weight: .semibold
                    )
                    .foregroundStyle(theme.fg2)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(theme.chipBg)
                    )
                    .padding(.top, 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
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
        }
    }
}
