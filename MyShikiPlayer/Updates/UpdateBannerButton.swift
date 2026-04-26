//
//  UpdateBannerButton.swift
//  MyShikiPlayer
//
//  TopBar pill that appears only when UpdateCheckService has a newer release
//  pending. Click → menu with "Open release page" / "Skip this version".
//

import AppKit
import SwiftUI

struct UpdateBannerButton: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var service: UpdateCheckService

    var body: some View {
        if let info = service.availableUpdate {
            Menu {
                Button("Открыть страницу релиза") {
                    NSWorkspace.shared.open(info.releaseURL)
                    NetworkLogStore.shared.logUIEvent("update_open_release \(info.version)")
                }
                Button("Пропустить версию \(info.version)") {
                    service.skipCurrentlyOffered()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Обновление \(info.version)")
                        .font(.dsBody(12, weight: .semibold))
                }
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.accent.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(theme.accent.opacity(0.35), lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Доступна новая версия \(info.displayName) — нажмите, чтобы открыть GitHub")
            .transition(.opacity)
        }
    }
}
