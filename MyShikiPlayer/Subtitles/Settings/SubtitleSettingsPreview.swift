//
//  SubtitleSettingsPreview.swift
//  MyShikiPlayer
//
//  Live preview pane that renders a sample cue with custom-style settings.
//  Always shows the custom (non-ASS) rendering regardless of useStudioStyle,
//  so the user can tune accessibility values even when studio mode is default.
//

import SwiftUI

struct SubtitleSettingsPreview: View {
  let settings: SubtitleSettings

  private let sampleText = "Пример субтитров с длинной второй строкой\nдля проверки переноса"

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("ПРЕВЬЮ СВОЕГО СТИЛЯ")
        .font(.dsMono(10, weight: .semibold))
        .tracking(1.2)
        .foregroundStyle(.secondary)

      GeometryReader { proxy in
        ZStack(alignment: .bottom) {
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black)

          previewCue(in: proxy.size)
        }
        .animation(.easeInOut(duration: 0.15), value: settings.fontFamily)
        .animation(.easeInOut(duration: 0.15), value: settings.fontSize)
        .animation(.easeInOut(duration: 0.15), value: settings.fontWeight)
        .animation(.easeInOut(duration: 0.15), value: settings.backgroundStyle)
        .animation(.easeInOut(duration: 0.15), value: settings.backgroundOpacity)
        .animation(.easeInOut(duration: 0.15), value: settings.shadowEnabled)
        .animation(.easeInOut(duration: 0.15), value: settings.verticalPosition)
      }
      .aspectRatio(16.0 / 9.0, contentMode: .fit)
      .frame(maxWidth: .infinity)
    }
  }

  // MARK: - Cue

  @ViewBuilder
  private func previewCue(in size: CGSize) -> some View {
    let bottomPadding = (1.0 - settings.verticalPosition) * size.height

    VStack {
      Spacer(minLength: 0)
      styledText
        .lineLimit(settings.maxLines)
        .truncationMode(.tail)
        .multilineTextAlignment(.center)
        .frame(maxWidth: size.width * 0.8)
        .background(backgroundView)
        .padding(.bottom, bottomPadding)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
  }

  // MARK: - Text styling (mirrors CustomSubtitleRenderer)

  private var styledText: some View {
    Text(sampleText)
      .font(
        .custom(settings.fontFamily, size: previewFontSize)
        .weight(settings.fontWeight.swiftUIWeight)
      )
      .foregroundStyle(settings.textColor)
      .shadow(
        color: settings.outlineColor,
        radius: 0,
        x: -settings.outlineWidth,
        y: -settings.outlineWidth
      )
      .shadow(
        color: settings.outlineColor,
        radius: 0,
        x: settings.outlineWidth,
        y: -settings.outlineWidth
      )
      .shadow(
        color: settings.outlineColor,
        radius: 0,
        x: -settings.outlineWidth,
        y: settings.outlineWidth
      )
      .shadow(
        color: settings.outlineColor,
        radius: 0,
        x: settings.outlineWidth,
        y: settings.outlineWidth
      )
      .shadow(
        color: settings.shadowEnabled ? .black.opacity(0.6) : .clear,
        radius: 4,
        x: 0,
        y: 2
      )
  }

  // Scale the font down for the 140pt-tall preview frame (real default is 28pt, container is ~250px wide).
  private var previewFontSize: CGFloat {
    // Preview height ~140pt → real frame height is much larger; scale proportionally.
    // Treat preview as 16:9 @ maxWidth ≤ 472pt → height ≤ 265pt.
    // Real player height ≈ 600pt → factor ≈ 0.38 ≈ 0.4.
    settings.fontSize * 0.4
  }

  // MARK: - Background (mirrors CustomSubtitleRenderer)

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
