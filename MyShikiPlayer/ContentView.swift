//
//  ContentView.swift
//  MyShikiPlayer
//

import AppKit
import SwiftUI

@MainActor
struct ContentView: View {
    private enum StartupPhase {
        case loading
        case auth
        case app
    }

    @EnvironmentObject private var shikimoriAuth: ShikimoriAuthController
    @StateObject private var networkLogs = NetworkLogStore.shared
    @State private var isLogPanelExpanded = false
    @AppStorage("app.theme") private var themeId: String = AppTheme.paper.id
    @AppStorage("settings.networkLogsEnabled") private var networkLogsEnabled: Bool = false

    private var theme: AppTheme { AppTheme.byId(themeId) }

    var body: some View {
        Group {
            switch startupPhase {
            case .loading:
                LaunchLogoView()
                    .transition(.opacity)
            case .auth:
                authView
                    .transition(.opacity)
            case .app:
                AppShellView(auth: shikimoriAuth)
                    .transition(.opacity)
            }
        }
        .background(theme.bg)
        .appTheme(theme)
        .animation(.easeInOut(duration: 0.2), value: startupPhaseTag)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if networkLogsEnabled {
                NetworkLogPanel(
                    logs: networkLogs,
                    isExpanded: $isLogPanelExpanded
                )
            }
        }
        .task {
            await shikimoriAuth.restoreSession()
        }
        .onDisappear {
            // Closing the main window should not leave OAuth callback wait hanging.
            shikimoriAuth.cancelPendingSignIn()
        }
        .onOpenURL { url in
            shikimoriAuth.handleOAuthCallback(url)
        }
        .alert("Ошибка", isPresented: Binding(
            get: { shikimoriAuth.alertMessage != nil },
            set: { if !$0 { shikimoriAuth.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { shikimoriAuth.alertMessage = nil }
        } message: {
            Text(shikimoriAuth.alertMessage ?? "")
        }
    }

    private var authView: some View {
        Group {
            if !shikimoriAuth.isConfigured {
                AuthGateView(
                    title: "Shikimori не настроен",
                    message: "Missing client_id / client_secret in the build. Fill Configuration/Secrets.xcconfig and rebuild the app.",
                    isBusy: false,
                    buttonTitle: nil,
                    buttonAction: nil
                )
            } else if shikimoriAuth.requiresReauth {
                AuthGateView(
                    title: "Сессия истекла",
                    message: "Войдите в Shikimori заново — токен больше не действителен.",
                    isBusy: shikimoriAuth.isAuthorizing,
                    buttonTitle: "Войти заново",
                    buttonAction: { Task { await shikimoriAuth.signIn() } }
                )
            } else {
                AuthGateView(
                    title: "Вход в Shikimori",
                    message: "Чтобы продолжить, авторизуйтесь через OAuth2.",
                    isBusy: shikimoriAuth.isAuthorizing,
                    buttonTitle: "Войти через Shikimori",
                    buttonAction: { Task { await shikimoriAuth.signIn() } }
                )
            }
        }
    }

    private var startupPhase: StartupPhase {
        if shikimoriAuth.isRestoringSession {
            return .loading
        }
        return shikimoriAuth.isLoggedIn ? .app : .auth
    }

    private var startupPhaseTag: Int {
        switch startupPhase {
        case .loading: return 0
        case .auth: return 1
        case .app: return 2
        }
    }
}

struct UserToolbarProfileView: View {
    let user: CurrentUser

    var body: some View {
        HStack(spacing: 8) {
            avatarView
            Text(user.nickname)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let url = avatarURL {
            CachedRemoteImage(
                url: url,
                contentMode: .fill,
                placeholder: {
                    Circle().fill(Color.secondary.opacity(0.2))
                        .overlay {
                            ProgressView().controlSize(.mini)
                        }
                },
                failure: {
                    fallbackAvatar
                }
            )
            .frame(width: 20, height: 20)
            .clipped()
            .clipShape(Circle())
        } else {
            fallbackAvatar
        }
    }

    private var fallbackAvatar: some View {
        Circle()
            .fill(Color.secondary.opacity(0.2))
            .overlay {
                Text(initials)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 20, height: 20)
    }

    private var avatarURL: URL? {
        let raw = user.image?.x48
            ?? user.image?.x64
            ?? user.image?.x80
            ?? user.image?.x160
            ?? user.avatar
        return raw?.shikimoriResolvedURL
    }

    private var initials: String {
        let parts = user.nickname.split(separator: " ")
        if parts.count >= 2 {
            let first = parts[0].prefix(1)
            let second = parts[1].prefix(1)
            return "\(first)\(second)".uppercased()
        }
        return String(user.nickname.prefix(1)).uppercased()
    }
}

private struct NetworkLogPanel: View {
    @ObservedObject var logs: NetworkLogStore
    @Binding var isExpanded: Bool
    @State private var filter: String = ""

    private var trimmedFilter: String {
        filter.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredEntries: [NetworkLogStore.Entry] {
        let needle = trimmedFilter
        guard !needle.isEmpty else { return logs.entries }
        return logs.entries.filter { entry in
            entry.line.range(of: needle, options: .caseInsensitive) != nil
        }
    }

    private var counterLabel: String {
        let total = logs.entries.count
        let shown = filteredEntries.count
        if shown == total {
            return "Сетевые логи (\(total))"
        }
        return "Сетевые логи (\(shown)/\(total))"
    }

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            if isExpanded {
                Divider()
                filterRow
                Divider()
                logList
            }
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "network")
                    Text(counterLabel)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button("Copy") {
                let text = filteredEntries.map(\.line).joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .disabled(filteredEntries.isEmpty)
            .help(trimmedFilter.isEmpty ? "Copy all log entries" : "Copy entries matching the filter")

            if isExpanded {
                Button("Clear") {
                    logs.clear()
                }
                .disabled(logs.entries.isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private var filterRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
            TextField("Фильтр (подстрока, без учёта регистра)", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
            if !filter.isEmpty {
                Button {
                    filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Очистить фильтр")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredEntries) { entry in
                        Text(entry.line)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: logs.entries.count) { _ in
                // Stick to the bottom only when the newest entry is visible
                // under the current filter; otherwise the user is likely
                // inspecting a filtered slice and a sudden jump is jarring.
                guard let last = logs.entries.last,
                      filteredEntries.contains(where: { $0.id == last.id })
                else { return }
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .frame(height: 170)
    }
}

private struct AuthGateView: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let message: String
    let isBusy: Bool
    let buttonTitle: String?
    let buttonAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.key.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text(title)
                .font(.title3.weight(.semibold))

            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)

            if let buttonTitle, let buttonAction {
                Button(action: buttonAction) {
                    Text(buttonTitle)
                        .frame(minWidth: 210)
                }
                .buttonStyle(.accent)
                .disabled(isBusy)
            }

            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .hidden()
                }
            }
            .frame(height: 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(theme.bg)
    }
}

private struct LaunchLogoView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 200, height: 200)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
    }
}

#Preview {
    ContentView()
        .environmentObject(ShikimoriAuthController())
}
