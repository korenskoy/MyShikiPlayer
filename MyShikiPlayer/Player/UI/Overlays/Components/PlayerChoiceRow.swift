//
//  PlayerChoiceRow.swift
//  MyShikiPlayer
//
//  Shared row rendering for PlayerChoiceList and SubtitleTrackPicker.
//  Always dark-themed (player context).
//

import SwiftUI

struct PlayerChoiceRow: View {
  let title: String
  let subtitle: String?
  let isSelected: Bool
  let onSelect: () -> Void

  var body: some View {
    Button(action: onSelect) {
      HStack(spacing: 10) {
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.dsBody(12, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(Color.white)
            .lineLimit(1)
            .truncationMode(.tail)
          if let subtitle, !subtitle.isEmpty {
            Text(subtitle)
              .font(.dsMono(9, weight: .medium))
              .foregroundStyle(Color.white.opacity(0.5))
          }
        }
        Spacer()
        if isSelected {
          DSIcon(name: .check, size: 12, weight: .bold)
            .foregroundStyle(Color(hex: 0xFF4D5E))
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .contentShape(Rectangle())
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(isSelected ? Color.white.opacity(0.06) : Color.clear)
      )
    }
    .buttonStyle(.plain)
  }
}
