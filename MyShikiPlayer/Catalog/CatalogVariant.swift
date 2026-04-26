//
//  CatalogVariant.swift
//  MyShikiPlayer
//
//  Three catalog grid variants (from screens-catalog.jsx):
//  grid (5x), dense (8x) and rows. Selection persisted via @AppStorage.
//

import SwiftUI

enum CatalogVariant: String, CaseIterable, Identifiable {
    case grid
    case dense
    case rows

    var id: String { rawValue }

    var hint: String {
        switch self {
        case .grid:  return "Крупная сетка"
        case .dense: return "Плотная сетка"
        case .rows:  return "Строки"
        }
    }
}

struct CatalogVariantToggle: View {
    @Environment(\.appTheme) private var theme
    @Binding var selection: CatalogVariant

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CatalogVariant.allCases) { variant in
                button(for: variant)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(theme.chipBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(theme.chipBr, lineWidth: 1)
        )
    }

    private func button(for variant: CatalogVariant) -> some View {
        let isActive = selection == variant
        let fg = isActive ? activeForeground : theme.fg2
        return Button {
            selection = variant
        } label: {
            glyph(for: variant, color: fg)
                .frame(width: 32, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? theme.accent : Color.clear)
                )
                // Explicit hit-target = the entire button rectangle, otherwise
                // clicks near the edges do not register (Button only catches
                // visible subviews by default).
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(variant.hint)
    }

    @ViewBuilder
    private func glyph(for variant: CatalogVariant, color: Color) -> some View {
        switch variant {
        case .grid:
            DSIcon(name: .grid, size: 14, weight: .semibold)
                .foregroundStyle(color)
        case .dense:
            denseGlyph(color: color)
        case .rows:
            DSIcon(name: .list, size: 14, weight: .semibold)
                .foregroundStyle(color)
        }
    }

    /// Mini 3x3 grid of small squares. Color is passed explicitly so the
    /// active state paints them with the same foreground as SF Symbols.
    private func denseGlyph(color: Color) -> some View {
        VStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(color)
                            .frame(width: 3, height: 3)
                    }
                }
            }
        }
    }

    private var activeForeground: Color {
        theme.mode == .dark ? Color(hex: 0x0B0A0D) : Color.white
    }
}
