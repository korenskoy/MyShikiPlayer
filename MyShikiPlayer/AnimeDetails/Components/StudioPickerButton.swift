//
//  StudioPickerButton.swift
//  MyShikiPlayer
//
//  Popover for choosing a dub studio before playback starts.
//  List comes from KodikCatalogEntry. Updates VM.selectedTranslationId.
//

import SwiftUI

struct StudioPickerButton: View {
    @Environment(\.appTheme) private var theme
    let entries: [KodikCatalogEntry]
    let selectedId: Int?
    let onSelect: (Int?) -> Void

    @State private var showing = false

    private var currentEntry: KodikCatalogEntry? {
        if let id = selectedId, let e = entries.first(where: { $0.translation.id == id }) {
            return e
        }
        return entries.first
    }

    private var currentName: String {
        currentEntry?.translation.title ?? "—"
    }

    private var currentKind: KodikTranslationKind? {
        currentEntry?.translation.kind
    }

    private var hasOptions: Bool { !entries.isEmpty }

    private static func badgeText(for kind: KodikTranslationKind) -> String {
        switch kind {
        case .voice: return "ОЗВ"
        case .subtitles: return "СУБ"
        }
    }

    private static func subtitlePrefix(for kind: KodikTranslationKind) -> String {
        switch kind {
        case .voice: return "Озвучка"
        case .subtitles: return "Субтитры"
        }
    }

    var body: some View {
        Button {
            guard hasOptions else { return }
            showing.toggle()
        } label: {
            HStack(spacing: 8) {
                DSIcon(name: .mic, size: 14, weight: .semibold)
                VStack(alignment: .leading, spacing: 0) {
                    Text("ОЗВУЧКА")
                        .dsMonoLabel(size: 9, tracking: 1.2)
                        .foregroundStyle(theme.fg3)
                    HStack(spacing: 6) {
                        Text(currentName)
                            .font(.dsBody(12, weight: .semibold))
                            .foregroundStyle(theme.fg)
                            .lineLimit(1)
                        if let kind = currentKind {
                            Text(Self.badgeText(for: kind))
                                .dsMonoLabel(size: 9, tracking: 1.0)
                                .foregroundStyle(theme.fg3)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .stroke(theme.chipBr, lineWidth: 1)
                                )
                        }
                    }
                }
                if hasOptions {
                    DSIcon(name: .chevD, size: 11, weight: .regular)
                        .foregroundStyle(theme.fg3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.chipBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.chipBr, lineWidth: 1)
            )
            .opacity(hasOptions ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!hasOptions)
        .popover(isPresented: $showing, arrowEdge: .top) {
            DetailsChoiceList(
                header: "ОЗВУЧКА",
                items: entries,
                titleFor: { $0.translation.title },
                subtitleFor: { e in
                    let count = "\(e.episodes.count) серий"
                    guard let kind = e.translation.kind else { return count }
                    return "\(Self.subtitlePrefix(for: kind)) · \(count)"
                },
                isSelected: { $0.translation.id == selectedId },
                onSelect: { entry in
                    showing = false
                    onSelect(entry.translation.id)
                }
            )
        }
    }
}
