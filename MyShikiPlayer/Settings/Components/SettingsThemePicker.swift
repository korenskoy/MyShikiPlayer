//
//  SettingsThemePicker.swift
//  MyShikiPlayer
//
//  Two-mode theme picker:
//      • "Системная тема" toggle ON  — pick a family (Otaku / Plum); the
//        active palette flips between dark/light with the system appearance.
//        Stored as `auto.otaku` / `auto.plum`.
//      • Toggle OFF — pick one of the four fixed palettes via radio rows.
//        Stored as the palette id directly.
//
//  ContentView / AppShellView read the same `app.theme` key and resolve
//  `auto.*` ids via AppTheme.resolve(id:systemScheme:).
//

import SwiftUI

struct SettingsThemePicker: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var systemScheme
    @AppStorage("app.theme") private var themeId: String = AppTheme.autoOtakuId

    private var followsSystem: Bool { themeId.hasPrefix("auto.") }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            systemToggleRow
            if followsSystem {
                familyPicker
            } else {
                fixedRadioGroup
            }
        }
    }

    // MARK: - System toggle

    private var systemToggleRow: some View {
        Toggle(isOn: Binding(
            get: { followsSystem },
            set: { newValue in
                themeId = newValue
                    ? autoIdFor(currentFixed: themeId)
                    : fixedIdFor(currentAuto: themeId)
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Системная тема")
                    .font(.dsBody(13, weight: .medium))
                    .foregroundStyle(theme.fg)
                Text(followsSystem
                     ? "Светлая или тёмная — по системе. Сейчас: \(AppTheme.resolve(id: themeId, systemScheme: systemScheme).name)."
                     : "Тема не зависит от системного оформления.")
                    .font(.dsLabel(10))
                    .foregroundStyle(theme.fg3)
            }
        }
        .toggleStyle(.switch)
    }

    // MARK: - Family picker (toggle ON)

    private var familyPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(AppTheme.autoIds, id: \.self) { id in
                familyRow(id: id)
            }
        }
    }

    private func familyRow(id: String) -> some View {
        let isSelected = themeId == id
        let pair = autoPair(for: id)
        return rowShell(
            isSelected: isSelected,
            onTap: { themeId = id },
            content: {
                HStack(spacing: 12) {
                    autoSwatch(pair: pair)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(familyDisplayName(for: id))
                            .font(.dsBody(13, weight: .medium))
                            .foregroundStyle(theme.fg)
                        Text(familySubtitle(for: id))
                            .font(.dsLabel(10))
                            .foregroundStyle(theme.fg3)
                    }
                    Spacer()
                    selectionDot(isSelected: isSelected)
                }
            }
        )
    }

    // MARK: - Fixed radio group (toggle OFF)

    private var fixedRadioGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(AppTheme.allFixed, id: \.id) { candidate in
                fixedRow(for: candidate)
            }
        }
    }

    private func fixedRow(for candidate: AppTheme) -> some View {
        let isSelected = themeId == candidate.id
        return rowShell(
            isSelected: isSelected,
            onTap: { themeId = candidate.id },
            content: {
                HStack(spacing: 12) {
                    swatch(for: candidate)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.name)
                            .font(.dsBody(13, weight: .medium))
                            .foregroundStyle(theme.fg)
                        Text(Self.fixedSubtitle(for: candidate))
                            .font(.dsLabel(10))
                            .foregroundStyle(theme.fg3)
                    }
                    Spacer()
                    selectionDot(isSelected: isSelected)
                }
            }
        )
    }

    // MARK: - Building blocks

    private func rowShell<Content: View>(
        isSelected: Bool,
        onTap: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: onTap) {
            content()
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? theme.accent.opacity(0.07) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? theme.accent : theme.line, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func selectionDot(isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .stroke(isSelected ? theme.accent : theme.line2, lineWidth: 1.5)
                .frame(width: 16, height: 16)
            if isSelected {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func swatch(for candidate: AppTheme) -> some View {
        HStack(spacing: 0) {
            candidate.bg.frame(width: 16, height: 28)
            candidate.card.frame(width: 16, height: 28)
            candidate.accent.frame(width: 16, height: 28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
    }

    private func autoSwatch(pair: (dark: AppTheme, light: AppTheme)) -> some View {
        HStack(spacing: 0) {
            pair.dark.bg.frame(width: 12, height: 28)
            pair.dark.accent.frame(width: 12, height: 28)
            pair.light.accent.frame(width: 12, height: 28)
            pair.light.bg.frame(width: 12, height: 28)
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
    }

    // MARK: - Mode transitions

    /// When the user switches the system-toggle ON: pick the auto-family that
    /// matches the currently-selected fixed palette.
    private func autoIdFor(currentFixed id: String) -> String {
        switch id {
        case "plum", "slate": return AppTheme.autoPlumId
        default:              return AppTheme.autoOtakuId
        }
    }

    /// When the user switches the system-toggle OFF: pick a fixed palette that
    /// matches the currently-active resolved palette under the auto family.
    private func fixedIdFor(currentAuto id: String) -> String {
        AppTheme.resolve(id: id, systemScheme: systemScheme).id
    }

    // MARK: - Names / subtitles

    private func autoPair(for id: String) -> (dark: AppTheme, light: AppTheme) {
        switch id {
        case AppTheme.autoOtakuId: return (.midnight, .paper)
        case AppTheme.autoPlumId:  return (.plum, .slate)
        default:                   return (.midnight, .paper)
        }
    }

    private func familyDisplayName(for id: String) -> String {
        switch id {
        case AppTheme.autoOtakuId: return "Otaku"
        case AppTheme.autoPlumId:  return "Plum"
        default:                   return id
        }
    }

    private func familySubtitle(for id: String) -> String {
        switch id {
        case AppTheme.autoOtakuId: return "Красный акцент · Midnight ↔ Daylight"
        case AppTheme.autoPlumId:  return "Циановый акцент · Neon Plum ↔ Daylight Plum"
        default:                   return ""
        }
    }

    private static func fixedSubtitle(for candidate: AppTheme) -> String {
        switch candidate.id {
        case "midnight": return "Тёмная · красный акцент"
        case "plum":     return "Тёмная · циан"
        case "paper":    return "Светлая · красный акцент"
        case "slate":    return "Светлая · циан"
        default:         return ""
        }
    }
}
