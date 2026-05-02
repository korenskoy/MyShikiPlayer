//
//  CustomSubtitleRenderer.swift
//  MyShikiPlayer
//

import SwiftUI

/// SwiftUI Text-based subtitle renderer. Honours all SubtitleSettings style properties.
/// Used when studio style is disabled or the track has no ASS URL.
struct CustomSubtitleRenderer: View {
  @ObservedObject var engine: PlayerEngine
  let store: SubtitleStore
  let settings: SubtitleSettings

  var body: some View {
    GeometryReader { proxy in
      let cue = store.cue(atVideoTime: engine.currentTime)
      cueLabel(cue: cue, in: proxy.size)
        .id(cue?.id)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: cue?.id)
    }
  }

  // MARK: - Cue label

  @ViewBuilder
  private func cueLabel(cue: SubtitleCue?, in size: CGSize) -> some View {
    let bottomPadding = (1.0 - settings.verticalPosition) * size.height

    VStack {
      Spacer(minLength: 0)
      styledText(for: cue)
        .lineLimit(settings.maxLines)
        .truncationMode(.tail)
        .multilineTextAlignment(.center)
        .frame(maxWidth: size.width * 0.8)
        .background(backgroundView)
        .padding(.bottom, bottomPadding)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
  }

  // MARK: - Text styling

  private func styledText(for cue: SubtitleCue?) -> some View {
    let content = cue?.text ?? ""
    return Text(content)
      .font(.custom(settings.fontFamily, size: settings.fontSize).weight(settings.fontWeight.swiftUIWeight))
      .foregroundStyle(settings.textColor)
      .shadow(color: settings.outlineColor, radius: 0, x: -settings.outlineWidth, y: -settings.outlineWidth)
      .shadow(color: settings.outlineColor, radius: 0, x: settings.outlineWidth, y: -settings.outlineWidth)
      .shadow(color: settings.outlineColor, radius: 0, x: -settings.outlineWidth, y: settings.outlineWidth)
      .shadow(color: settings.outlineColor, radius: 0, x: settings.outlineWidth, y: settings.outlineWidth)
      .shadow(
        color: settings.shadowEnabled ? .black.opacity(0.6) : .clear,
        radius: 4,
        x: 0,
        y: 2
      )
  }

  // MARK: - Background

  @ViewBuilder
  private var backgroundView: some View {
    switch settings.backgroundStyle {
    case .none, .shadow:
      EmptyView()
    case .box:
      RoundedRectangle(cornerRadius: 6)
        .fill(.black.opacity(settings.backgroundOpacity))
        .padding(.horizontal, -12)
        .padding(.vertical, -6)
    }
  }
}
