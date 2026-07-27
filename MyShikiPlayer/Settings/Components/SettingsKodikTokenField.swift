//
//  SettingsKodikTokenField.swift
//  MyShikiPlayer
//
//  Kodik API-token field with an inline × clear button.
//  Owns its own draft / autosave-flash state — the persisted token lives in
//  the Keychain (`KodikTokenStore`), mirrored here by `storedToken` so the
//  autosave path can skip no-op writes.
//

import SwiftUI

struct SettingsKodikTokenField: View {
    /// Unlike the previous `@AppStorage` backing, a Keychain write can fail —
    /// so the autosave row has to be able to say so instead of flashing a
    /// green "saved" it cannot back up.
    private enum SaveFlash {
        case saved
        case failed
    }

    @Environment(\.appTheme) private var theme
    @State private var draftToken: String = ""
    @State private var storedToken: String = ""
    @State private var saveFlash: SaveFlash?
    @FocusState private var fieldFocused: Bool

    private let store = KodikTokenStore.shared

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
                switch saveFlash {
                case .saved:
                    Label("Сохранено", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                case .failed:
                    Label("Не удалось сохранить", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                case nil:
                    EmptyView()
                }
            }
            .frame(height: 18, alignment: .leading)
        }
        .task {
            KodikTokenManager.migrateLegacyTokenIfNeeded(store: store)
            let loaded = store.load() ?? ""
            storedToken = loaded
            draftToken = loaded
        }
    }

    private var clearButton: some View {
        Button {
            draftToken = ""
            guard store.clear() else {
                NetworkLogStore.shared.logUIEvent("kodik_token_clear_failed")
                flash(.failed)
                return
            }
            storedToken = ""
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
        guard storedToken != trimmed else { return }
        guard store.save(trimmed) else {
            NetworkLogStore.shared.logUIEvent("kodik_token_save_failed")
            flash(.failed)
            return
        }
        storedToken = trimmed
        NetworkLogStore.shared.logUIEvent("kodik_token_saved")
        flash(.saved)
    }

    private func flash(_ state: SaveFlash) {
        saveFlash = state
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            saveFlash = nil
        }
    }
}
