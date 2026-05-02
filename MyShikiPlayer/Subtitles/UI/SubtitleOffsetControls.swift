//
//  SubtitleOffsetControls.swift
//  MyShikiPlayer
//
//  Horizontal row of offset-adjustment buttons shown inside the CC popover.
//

import SwiftUI

struct SubtitleOffsetControls: View {
  let store: SubtitleStore
  var disabled: Bool = false

  private var formattedOffset: String {
    let v = store.timeOffset
    if v == 0 { return "0 сек" }
    let sign = v > 0 ? "+" : "−"
    return "\(sign)\(String(format: "%.1f", abs(v))) сек"
  }

  var body: some View {
    HStack(spacing: 6) {
      offsetButton(label: "−5s") { store.adjustOffset(by: -5) }
      offsetButton(label: "−0.5s") { store.adjustOffset(by: -0.5) }

      Text("Сдвиг: \(formattedOffset)")
        .font(.dsMono(10, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.7))
        .frame(maxWidth: .infinity)
        .lineLimit(1)
        .minimumScaleFactor(0.8)

      offsetButton(label: "+0.5s") { store.adjustOffset(by: 0.5) }
      offsetButton(label: "+5s") { store.adjustOffset(by: 5) }

      resetButton
    }
    .disabled(disabled)
    .opacity(disabled ? 0.4 : 1)
  }

  private func offsetButton(label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(label)
        .font(.dsMono(9, weight: .semibold))
        .foregroundStyle(Color.white)
        .frame(width: 40, height: 26)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.white.opacity(0.08))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
  }

  private var resetButton: some View {
    Button(action: { store.resetOffset() }) {
      Text("Сброс")
        .font(.dsMono(9, weight: .semibold))
        .foregroundStyle(Color(hex: 0xFF4D5E))
        .frame(width: 44, height: 26)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(hex: 0xFF4D5E).opacity(0.1))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(Color(hex: 0xFF4D5E).opacity(0.25), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
  }
}
