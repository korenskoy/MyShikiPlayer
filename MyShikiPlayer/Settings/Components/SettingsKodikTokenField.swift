//
//  SettingsKodikTokenField.swift
//  MyShikiPlayer
//
//  Kodik API-token field with an inline × clear button.
//  Owns its own draft / autosave-flash state — the single source of truth
//  for the persisted token is `@AppStorage("kodik.apiToken")`.
//

import SwiftUI

struct SettingsKodikTokenField: View {
    @Environment(\.appTheme) private var theme
    @AppStorage("kodik.apiToken") private var kodikApiToken: String = ""
    @State private var draftToken: String = ""
    @State private var autosaveFeedback = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Kodik API токен")
                .font(.dsLabel(11, weight: .semibold))
                .foregroundStyle(theme.fg2)

            SecureField("API токен Kodik", text: $draftToken)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit(persist)
                .onChange(of: fieldFocused) { _, isFocused in
                    if !isFocused { persist() }
                }
                .overlay(alignment: .trailing) {
                    if !draftToken.isEmpty {
                        clearButton
                    }
                }

            // Reserve a constant-height row for the autosave feedback so the
            // section never reflows when the user finishes editing.
            HStack(spacing: 6) {
                if autosaveFeedback {
                    Label("Сохранено", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
            .frame(height: 18, alignment: .leading)
        }
        .task {
            draftToken = kodikApiToken
        }
    }

    private var clearButton: some View {
        Button {
            draftToken = ""
            kodikApiToken = ""
            NetworkLogStore.shared.logUIEvent("kodik_token_cleared")
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(theme.fg3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 6)
        .help("Очистить токен")
    }

    private func persist() {
        let trimmed = draftToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kodikApiToken != trimmed else { return }
        kodikApiToken = trimmed
        NetworkLogStore.shared.logUIEvent("kodik_token_saved")
        autosaveFeedback = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            autosaveFeedback = false
        }
    }
}
