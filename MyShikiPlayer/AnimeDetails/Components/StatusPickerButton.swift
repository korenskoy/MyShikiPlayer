//
//  StatusPickerButton.swift
//  MyShikiPlayer
//
//  Popover button for picking the title's status in the user's list.
//  Tap → popover with the list of statuses plus a "Remove from list" entry.
//

import SwiftUI

struct StatusPickerButton: View {
    @Environment(\.appTheme) private var theme
    let currentStatus: String?
    let isUpdating: Bool
    let onSelect: (String?) -> Void

    @State private var showing = false

    /// Statuses in the expected order. The `nil` entry (= "Remove from list")
    /// is shown only when the title is already in the list — otherwise there
    /// is nothing to remove.
    private var options: [String?] {
        var list: [String?] = [
            "planned", "watching", "rewatching", "completed", "on_hold", "dropped",
        ]
        if currentStatus != nil {
            list.append(nil)
        }
        return list
    }

    /// Button label text. In the popover `nil` = "Remove from list", but on
    /// the button itself for a not-in-list title that is meaningless — there
    /// we show the "Add to list" prompt instead.
    private var title: String {
        currentStatus == nil ? "В список" : Self.label(for: currentStatus)
    }

    private var icon: DSIconName {
        currentStatus == nil ? .plus : .bookmark
    }

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 8) {
                DSIcon(name: icon, size: 14, weight: .semibold)
                Text(title)
                    .font(.dsBody(13, weight: .semibold))
                if isUpdating {
                    ProgressView().controlSize(.mini)
                } else {
                    DSIcon(name: .chevD, size: 11, weight: .regular)
                }
            }
            .foregroundStyle(theme.fg)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.chipBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.chipBr, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isUpdating)
        .popover(isPresented: $showing, arrowEdge: .top) {
            DetailsChoiceList(
                header: "В МОЁМ СПИСКЕ",
                items: options,
                titleFor: { Self.label(for: $0) },
                subtitleFor: nil,
                isSelected: { ($0 ?? "") == (currentStatus ?? "") },
                onSelect: { selected in
                    showing = false
                    onSelect(selected)
                }
            )
        }
    }

    static func label(for status: String?) -> String {
        switch status {
        case nil:          return "Убрать из списка"
        case "watching":   return "Смотрю"
        case "planned":    return "Запланировано"
        case "rewatching": return "Пересматриваю"
        case "completed":  return "Просмотрено"
        case "on_hold":    return "Отложено"
        case "dropped":    return "Брошено"
        case .some(let s): return s.capitalized
        }
    }
}
