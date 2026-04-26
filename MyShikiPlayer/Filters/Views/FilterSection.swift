//
//  FilterSection.swift
//  MyShikiPlayer
//

import SwiftUI

/// Collapsible section header + content — used by every filter group in the sidebar.
struct FilterSection<Content: View>: View {
    let title: String
    let activeCount: Int
    @Binding var isExpanded: Bool
    let content: Content

    init(
        title: String,
        activeCount: Int = 0,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.activeCount = activeCount
        self._isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    if activeCount > 0 {
                        Text("\(activeCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
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

/// Checkbox row used inside filter sections — supports multi-select facets.
struct FilterCheckboxRow: View {
    let title: String
    let isOn: Bool
    let hint: String?
    let onToggle: () -> Void

    init(title: String, isOn: Bool, hint: String? = nil, onToggle: @escaping () -> Void) {
        self.title = title
        self.isOn = isOn
        self.hint = hint
        self.onToggle = onToggle
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let hint {
                    Text(hint)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
