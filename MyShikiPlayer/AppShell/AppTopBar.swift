//
//  AppTopBar.swift
//  MyShikiPlayer
//
//  Sticky top bar: Wordmark + browser-style history (back/forward with
//  hover-tooltip) + 5 navigation tabs + search-pill (⌘K) + avatar.
//  Replaces the NavigationSplitView sidebar.
//

import AppKit
import SwiftUI

struct AppTopBar: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var navigation: NavigationState
    @ObservedObject var auth: ShikimoriAuthController
    @ObservedObject var history: NavigationHistoryStore
    /// True while a detail page is on top of the branch view. The active tab
    /// highlight is hidden in that case — the user is "off-tab".
    var isDetailVisible: Bool = false
    var onGoBack: () -> Void = {}
    var onGoForward: () -> Void = {}
    var onOpenSearch: () -> Void = {}

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            Wordmark()

            historyButtons
                .transition(.opacity)

            navLinks
                .padding(.leading, 8)

            Spacer(minLength: 16)

            searchPill
                .frame(width: 280)

            trailingActions
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(
            theme.bg.opacity(0.9)
                .background(.regularMaterial)
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.line)
                .frame(height: 1)
        }
    }

    // MARK: - Navigation links

    private var navLinks: some View {
        HStack(spacing: 4) {
            ForEach(NavigationState.Branch.navBarCases) { branch in
                navButton(for: branch)
            }
        }
    }

    private func navButton(for branch: NavigationState.Branch) -> some View {
        let isActive = navigation.selectedBranch == branch && !isDetailVisible
        return Button {
            navigation.selectedBranch = branch
        } label: {
            HStack(spacing: 7) {
                if let icon = DSIconName(rawValue: branch.iconName) {
                    DSIcon(name: icon, size: 14, weight: .medium)
                }
                Text(branch.title)
                    .font(.dsBody(13, weight: .medium))
            }
            .foregroundStyle(isActive ? theme.fg : theme.fg2)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? theme.chipBg : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search trigger

    private var searchPill: some View {
        Button(action: onOpenSearch) {
            HStack(spacing: 8) {
                DSIcon(name: .search, size: 15, weight: .medium)
                    .foregroundStyle(theme.fg3)
                Text("Найти аниме, студию, тег…")
                    .font(.dsBody(13))
                    .foregroundStyle(theme.fg3)
                Spacer()
                Text("⌘K")
                    .font(.dsMono(10, weight: .semibold))
                    .foregroundStyle(theme.fg3)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(theme.line, lineWidth: 1)
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.chipBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Открыть поиск (⌘K)")
    }

    // MARK: - Trailing: progress + avatar

    private var trailingActions: some View {
        HStack(spacing: 10) {
            if auth.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            avatarButton
        }
    }

    private var avatarButton: some View {
        let isActive = navigation.selectedBranch == .profile && !isDetailVisible
        return Button {
            navigation.selectedBranch = .profile
        } label: {
            avatarCircle
                .overlay(
                    Circle()
                        .stroke(
                            isActive ? theme.accent : Color.clear,
                            lineWidth: 2
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Профиль")
    }

    @ViewBuilder
    private var avatarCircle: some View {
        if let url = avatarURL(for: auth.profile) {
            CachedRemoteImage(
                url: url,
                contentMode: .fill,
                placeholder: { fallbackAvatar },
                failure: { fallbackAvatar }
            )
            .frame(width: 30, height: 30)
            .clipShape(Circle())
        } else {
            fallbackAvatar
        }
    }

    private func avatarURL(for user: CurrentUser?) -> URL? {
        guard let user else { return nil }
        let raw = user.image?.x48
            ?? user.image?.x64
            ?? user.image?.x80
            ?? user.image?.x160
            ?? user.avatar
        guard let raw else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        if raw.hasPrefix("/") {
            return ShikimoriURL.media(path: raw)
        }
        return URL(string: raw)
    }

    private var fallbackAvatar: some View {
        let initial = auth.profile?.nickname.first.map { String($0).uppercased() } ?? "?"
        return ZStack {
            Circle()
                .fill(theme.accent)
                .frame(width: 30, height: 30)
            Text(initial)
                .font(.dsTitle(13, weight: .heavy))
                .foregroundStyle(Color.white)
        }
    }

    // MARK: - Global history controls

    private var historyButtons: some View {
        HStack(spacing: 2) {
            HistoryIconButton(
                icon: .chevL,
                enabled: history.canGoBack,
                helpText: helpText(prefix: "Назад", title: history.previousEntry?.tooltipTitle),
                action: onGoBack
            )

            HistoryIconButton(
                icon: .chevR,
                enabled: history.canGoForward,
                helpText: helpText(prefix: "Вперёд", title: history.nextEntry?.tooltipTitle),
                action: onGoForward
            )
        }
        .padding(.leading, 4)
        .padding(.trailing, 4)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.line)
                .frame(width: 1, height: 18)
                .offset(x: -12)
        }
    }

    private func helpText(prefix: String, title: String?) -> String {
        guard let title, !title.isEmpty else { return prefix }
        return "\(prefix): \(title)"
    }
}

// MARK: - HistoryIconButton

/// Back/forward button with a system tooltip via `.help(...)`.
private struct HistoryIconButton: View {
    @Environment(\.appTheme) private var theme
    let icon: DSIconName
    let enabled: Bool
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            DSIcon(name: icon, size: 15, weight: .semibold)
                .foregroundStyle(enabled ? theme.fg2 : theme.fg3)
                .opacity(enabled ? 1.0 : 0.4)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(helpText)
    }
}
