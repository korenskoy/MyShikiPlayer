//
//  StarRatingSurface.swift
//  MyShikiPlayer
//
//  "RATE" block — a row of 10 square numbered buttons (Shikimori/MAL-style).
//  Hover shows the potential score, click sets it, clicking the same digit
//  again resets.
//

import SwiftUI

struct StarRatingSurface: View {
    @Environment(\.appTheme) private var theme
    let userScore: Int?
    let isUpdating: Bool
    let onSetScore: (Int?) -> Void

    @State private var hoveredScore: Int? = nil

    var body: some View {
        DSSurface(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ОЦЕНИТЬ")
                        .dsMonoLabel(size: 10, tracking: 1.5)
                        .foregroundStyle(theme.fg3)
                    Spacer()
                    if isUpdating {
                        ProgressView().controlSize(.mini)
                    }
                }

                cells

                footerText
            }
        }
    }

    private var cells: some View {
        HStack(spacing: 4) {
            ForEach(1...10, id: \.self) { value in
                numberCell(value: value)
            }
        }
    }

    private func numberCell(value: Int) -> some View {
        let effective = hoveredScore ?? userScore ?? 0
        let filled = value <= effective
        let isExact = userScore == value

        return Button {
            onSetScore(isExact ? nil : value)
        } label: {
            Text("\(value)")
                .font(.dsMono(13, weight: filled ? .bold : .semibold))
                .foregroundStyle(filled ? activeForeground : theme.fg3)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(filled ? theme.accent : theme.chipBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isExact ? theme.accent : theme.chipBr, lineWidth: isExact ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hoveredScore = inside ? value : nil
        }
        .help("Поставить \(value) · \(Self.descriptor(for: value))")
    }

    private var activeForeground: Color {
        theme.mode == .dark ? Color(hex: 0x0B0A0D) : .white
    }

    @ViewBuilder
    private var footerText: some View {
        if let hoveredScore {
            Text("Поставить: **\(hoveredScore)** · \(Self.descriptor(for: hoveredScore))")
                .font(.dsBody(11))
                .foregroundStyle(theme.fg2)
        } else if let userScore, userScore > 0 {
            Text("Ваша оценка: **\(userScore)** · \(Self.descriptor(for: userScore))")
                .font(.dsBody(11))
                .foregroundStyle(theme.fg2)
        } else {
            Text("Оценка не выставлена")
                .font(.dsBody(11))
                .foregroundStyle(theme.fg3)
        }
    }

    /// Verbal descriptor — same as Shikimori.
    static func descriptor(for score: Int) -> String {
        switch score {
        case 10: return "Шедевр"
        case 9:  return "Великолепно"
        case 8:  return "Очень хорошо"
        case 7:  return "Хорошо"
        case 6:  return "Нормально"
        case 5:  return "Средне"
        case 4:  return "Плохо"
        case 3:  return "Очень плохо"
        case 2:  return "Жалкие осколки"
        case 1:  return "Ужасно"
        default: return "—"
        }
    }
}
