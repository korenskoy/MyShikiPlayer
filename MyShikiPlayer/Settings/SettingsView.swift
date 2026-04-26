//
//  SettingsView.swift
//  MyShikiPlayer
//
//  Sheet-style settings: theme, Kodik token, cache (images + repo), account.
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var auth: ShikimoriAuthController
    @StateObject private var cacheModel = ImageCacheSettingsModel()
    @StateObject private var hostsModel = SettingsHostsModel()
    @AppStorage("kodik.apiToken") private var kodikApiToken: String = ""
    @AppStorage("settings.networkLogsEnabled") private var networkLogsEnabled: Bool = false
    @State private var draftKodikToken: String = ""
    @State private var tokenAutosaveFeedback = false
    @State private var repoCacheFlash = false
    @FocusState private var kodikTokenFieldFocused: Bool

    let onSignOut: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    appearanceSection
                    hostsSection
                    kodikSection
                    diagnosticsSection
                    cacheSection
                    accountSection
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .background(theme.bg)
        .task {
            draftKodikToken = kodikApiToken
            hostsModel.reloadFromDefaults()
            await cacheModel.refreshSize()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("SETTINGS")
                    .font(.dsLabel(10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(theme.accent)
                Text("Настройки")
                    .font(.dsTitle(20, weight: .bold))
                    .foregroundStyle(theme.fg)
            }
            Spacer()
            Button(action: onClose) {
                DSIcon(name: .xmark, size: 14, weight: .semibold)
                    .foregroundStyle(theme.fg2)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme.chipBg)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Закрыть (Esc)")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.line).frame(height: 1)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        SettingsSection(
            title: "Тема",
            description: "Плеер всегда остаётся в тёмной палитре независимо от выбора."
        ) {
            SettingsThemePicker()
        }
    }

    // MARK: - Hosts

    private var hostsSection: some View {
        SettingsSection(
            title: "Домены",
            description: "Свои хосты для Shikimori и Kodik. Изменения применятся при следующем запросе. Учётка не сбрасывается."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                hostField(
                    title: "Shikimori API",
                    placeholder: hostsModel.placeholder(.shikimoriAPI),
                    text: $hostsModel.shikimoriAPIDraft,
                    isValid: hostsModel.isValid(.shikimoriAPI),
                    onCommit: { hostsModel.commit(.shikimoriAPI) }
                )
                hostField(
                    title: "Shikimori OAuth",
                    placeholder: hostsModel.placeholder(.shikimoriOAuth),
                    text: $hostsModel.shikimoriOAuthDraft,
                    isValid: hostsModel.isValid(.shikimoriOAuth),
                    onCommit: { hostsModel.commit(.shikimoriOAuth) }
                )
                hostField(
                    title: "Kodik API",
                    placeholder: hostsModel.placeholder(.kodikAPI),
                    text: $hostsModel.kodikAPIDraft,
                    isValid: hostsModel.isValid(.kodikAPI),
                    onCommit: { hostsModel.commit(.kodikAPI) }
                )
                hostField(
                    title: "Kodik Referer",
                    placeholder: hostsModel.placeholder(.kodikReferer),
                    text: $hostsModel.kodikRefererDraft,
                    isValid: hostsModel.isValid(.kodikReferer),
                    onCommit: { hostsModel.commit(.kodikReferer) }
                )

                HStack(spacing: 10) {
                    Button("Сбросить", role: .destructive) {
                        hostsModel.resetAll()
                    }
                    .buttonStyle(.bordered)

                    if hostsModel.savedFlash {
                        Label("Сохранено", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }
                .frame(height: 28, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func hostField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        isValid: Bool,
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.dsLabel(11, weight: .semibold))
                .foregroundStyle(theme.fg2)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit(onCommit)
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(isValid ? Color.clear : Color.red, lineWidth: 1)
                )
            // Reserve a constant-height row for the validation label so the
            // section never reflows when the user mistypes a host.
            Text(isValid ? " " : "Невалидный домен")
                .font(.footnote)
                .foregroundStyle(isValid ? Color.clear : .red)
                .frame(height: 14, alignment: .leading)
        }
    }

    // MARK: - Kodik

    private var kodikSection: some View {
        SettingsSection(
            title: "Kodik",
            description: "API-токен для поиска видео-источников. Хранится локально."
        ) {
            SecureField("API токен Kodik", text: $draftKodikToken)
                .textFieldStyle(.roundedBorder)
                .focused($kodikTokenFieldFocused)
                .onSubmit { persistKodikToken() }
                .onChange(of: kodikTokenFieldFocused) { _, isFocused in
                    if !isFocused { persistKodikToken() }
                }

            HStack(spacing: 10) {
                Button("Очистить токен", role: .destructive) {
                    draftKodikToken = ""
                    kodikApiToken = ""
                    NetworkLogStore.shared.logUIEvent("kodik_token_cleared")
                }
                .buttonStyle(.bordered)

                if tokenAutosaveFeedback {
                    Label("Сохранено", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        SettingsSection(
            title: "Диагностика",
            description: "Панель сетевых логов в нижней части окна. По умолчанию выключена."
        ) {
            Toggle(isOn: $networkLogsEnabled) {
                Text("Показывать панель сетевых логов")
                    .font(.dsBody(13))
                    .foregroundStyle(theme.fg)
            }
            .toggleStyle(.switch)
        }
    }

    // MARK: - Cache

    private var cacheSection: some View {
        SettingsSection(
            title: "Кэш",
            description: "Картинки на диске и in-memory кэш данных."
        ) {
            HStack {
                Text("Картинки на диске")
                    .font(.dsBody(13))
                    .foregroundStyle(theme.fg)
                Spacer()
                Text(cacheModel.formattedSize)
                    .font(.dsMono(12, weight: .semibold))
                    .foregroundStyle(theme.fg2)
            }

            HStack(spacing: 10) {
                Button("Обновить размер") {
                    Task { await cacheModel.refreshSize() }
                }
                .buttonStyle(.bordered)

                Button("Очистить диск", role: .destructive) {
                    Task { await cacheModel.clearCache() }
                }
                .buttonStyle(.bordered)
                .disabled(cacheModel.isClearing)
            }

            Divider()

            HStack {
                Text("Кэш данных (Profile / Home / Schedule / Details)")
                    .font(.dsBody(12))
                    .foregroundStyle(theme.fg2)
                Spacer()
                if repoCacheFlash {
                    Label("Сброшено", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                }
            }
            Button("Сбросить кэш (in-memory + диск)") {
                CacheEvents.postClearAllCaches()
                NetworkLogStore.shared.logUIEvent("repo_cache_cleared")
                repoCacheFlash = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_400_000_000)
                    repoCacheFlash = false
                }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        SettingsSection(
            title: "Аккаунт",
            description: auth.profile.map { "Авторизован как \($0.nickname)." }
        ) {
            Button("Выйти из Shikimori", role: .destructive, action: onSignOut)
                .buttonStyle(.bordered)
                .disabled(auth.isBusy)
        }
    }

    // MARK: - Helpers

    private func persistKodikToken() {
        let trimmed = draftKodikToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kodikApiToken != trimmed else { return }
        kodikApiToken = trimmed
        NetworkLogStore.shared.logUIEvent("kodik_token_saved")
        tokenAutosaveFeedback = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            tokenAutosaveFeedback = false
        }
    }
}
