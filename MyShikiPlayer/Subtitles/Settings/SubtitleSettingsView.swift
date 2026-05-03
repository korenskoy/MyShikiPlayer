//
//  SubtitleSettingsView.swift
//  MyShikiPlayer
//
//  Settings section for subtitle display. Binds directly to SubtitleSettings.
//  All controls dim (not collapse) when studio style is active, preserving layout stability.
//

import SwiftUI

struct SubtitleSettingsView: View {
  @Bindable var settings: SubtitleSettings

  @State private var showResetConfirm = false

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      sourceSection
      studioStyleSection
      textSection
      SubtitleSettingsPreview(settings: settings)
      resetSection
    }
  }

  // MARK: - Source

  private var sourceSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("ИСТОЧНИК")
        .font(.dsLabel(10, weight: .bold))
        .tracking(1.5)
        .foregroundStyle(.secondary)

      Picker("Язык", selection: $settings.preferredLanguage) {
        Text("Авто (по локали системы)").tag(SubtitlePreferredLanguage.auto)
        Text("Русские").tag(SubtitlePreferredLanguage.subRu)
        Text("Английские").tag(SubtitlePreferredLanguage.subEn)
        Text("Не подбирать автоматически").tag(SubtitlePreferredLanguage.off)
      }
    }
  }

  // MARK: - Studio style

  private var studioStyleSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("СТУДИЙНЫЙ СТИЛЬ")
        .font(.dsLabel(10, weight: .bold))
        .tracking(1.5)
        .foregroundStyle(.secondary)

      Toggle(isOn: $settings.useStudioStyle) {
        Text("Использовать студийные стили (если доступны)")
          .font(.dsBody(13))
      }
      .toggleStyle(.switch)

      Text(
        settings.useStudioStyle
          ? "Когда у трека есть студийный стиль (ASS) — он используется. Настройки ниже применяются как fallback и при выключении переключателя."
          : "Студийные стили игнорируются. Все треки рисуются по настройкам ниже."
      )
      .font(.dsBody(11))
      .foregroundStyle(.secondary)
      .animation(.easeInOut(duration: 0.15), value: settings.useStudioStyle)
    }
  }

  // MARK: - Text

  private var textSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("ТЕКСТ")
        .font(.dsLabel(10, weight: .bold))
        .tracking(1.5)
        .foregroundStyle(.secondary)

      fontFamilyPicker
      fontSizeRow
      fontWeightPicker
      colorRow
      outlineColorRow
      outlineWidthRow
      shadowToggle
      backgroundStylePicker
      backgroundOpacityRow
      verticalPositionRow
      maxLinesRow
    }
  }

  private var fontFamilyPicker: some View {
    let families = [
      "SF Pro Display",
      "SF Pro Text",
      "SF Pro Rounded",
      "SF Mono",
      "Helvetica Neue",
      "Avenir Next",
      "Menlo"
    ]
    return Picker("Шрифт", selection: $settings.fontFamily) {
      ForEach(families, id: \.self) { family in
        Text(family).tag(family)
      }
    }
  }

  private var fontSizeRow: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Размер шрифта")
          .font(.dsBody(13))
        Spacer()
        Text("\(Int(settings.fontSize)) pt")
          .font(.dsTechMono(12, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 8) {
        Text("16")
          .font(.dsBody(11))
          .foregroundStyle(.secondary)
        Slider(value: $settings.fontSize, in: 16...56, step: 1)
        Text("56")
          .font(.dsBody(11))
          .foregroundStyle(.secondary)
      }
    }
  }

  private var fontWeightPicker: some View {
    Picker("Насыщенность", selection: $settings.fontWeight) {
      Text("Regular").tag(SubtitleFontWeight.regular)
      Text("Medium").tag(SubtitleFontWeight.medium)
      Text("Semibold").tag(SubtitleFontWeight.semibold)
      Text("Bold").tag(SubtitleFontWeight.bold)
      Text("Heavy").tag(SubtitleFontWeight.heavy)
    }
  }

  private var colorRow: some View {
    ColorPicker(
      "Цвет текста",
      selection: Binding(
        get: { settings.textColor },
        set: { settings.textColor = $0 }
      ),
      supportsOpacity: false
    )
    .font(.dsBody(13))
  }

  private var outlineColorRow: some View {
    ColorPicker(
      "Цвет обводки",
      selection: Binding(
        get: { settings.outlineColor },
        set: { settings.outlineColor = $0 }
      ),
      supportsOpacity: false
    )
    .font(.dsBody(13))
  }

  private var outlineWidthRow: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Ширина обводки")
          .font(.dsBody(13))
        Spacer()
        Text(String(format: "%.1f", settings.outlineWidth))
          .font(.dsTechMono(12, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      Slider(value: $settings.outlineWidth, in: 0...6, step: 0.5)
    }
  }

  private var shadowToggle: some View {
    Toggle(isOn: $settings.shadowEnabled) {
      Text("Тень текста")
        .font(.dsBody(13))
    }
    .toggleStyle(.switch)
  }

  private var backgroundStylePicker: some View {
    Picker("Фон", selection: $settings.backgroundStyle) {
      Text("Нет").tag(SubtitleBackgroundStyle.none)
      Text("Тень").tag(SubtitleBackgroundStyle.shadow)
      Text("Плашка").tag(SubtitleBackgroundStyle.box)
    }
    .pickerStyle(.segmented)
  }

  private var backgroundOpacityRow: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Прозрачность фона")
          .font(.dsBody(13))
        Spacer()
        Text("\(Int((settings.backgroundOpacity * 100).rounded()))%")
          .font(.dsTechMono(12, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      Slider(value: $settings.backgroundOpacity, in: 0...1, step: 0.05)
        .disabled(settings.backgroundStyle != .box)
        .opacity(settings.backgroundStyle != .box ? 0.4 : 1.0)
    }
  }

  private var verticalPositionRow: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("Положение по вертикали")
          .font(.dsBody(13))
        Spacer()
        Text(String(format: "%.0f%%", settings.verticalPosition * 100))
          .font(.dsTechMono(12, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      Slider(value: $settings.verticalPosition, in: 0.5...0.98, step: 0.01)
    }
  }

  private var maxLinesRow: some View {
    Stepper(
      "Максимум строк: \(settings.maxLines)",
      value: $settings.maxLines,
      in: 1...5
    )
    .font(.dsBody(13))
  }

  // MARK: - Reset

  private var resetSection: some View {
    HStack {
      Spacer()
      Button("Сбросить к дефолту", role: .destructive) {
        showResetConfirm = true
      }
      .confirmationDialog(
        "Сбросить настройки субтитров?",
        isPresented: $showResetConfirm,
        titleVisibility: .visible
      ) {
        Button("Вернуть все настройки субтитров к значениям по умолчанию?", role: .destructive) {
          settings.resetToDefaults()
        }
        Button("Отмена", role: .cancel) {}
      }
    }
  }
}
