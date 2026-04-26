//
//  DetailsHero.swift
//  MyShikiPlayer
//
//  Top "cinematic" section of the detail screen: blurred backdrop derived
//  from the same poster + gradient into the theme background + poster card
//  on the left, title/chips/meta/buttons on the right.
//

import AppKit
import SwiftUI

struct DetailsHero: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var vm: AnimeDetailsViewModel
    let onWatch: () -> Void
    let onToggleFavorite: () -> Void
    let onOpenOnShikimori: () -> Void
    let onCopyLink: () -> Void
    let statusButton: AnyView
    let studioButton: AnyView
    @Binding var linkCopiedFlash: Bool

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            gradient
            content
        }
        .frame(height: 440)
        .clipped()
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.line)
                .frame(height: 1)
        }
    }

    // MARK: - Layers

    private var backdrop: some View {
        Group {
            if let url = heroURL {
                CachedRemoteImage(
                    url: url,
                    contentMode: .fill,
                    placeholder: { theme.bg2 },
                    failure: { theme.bg2 }
                )
            } else {
                theme.bg2
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gradient: some View {
        LinearGradient(
            stops: [
                .init(color: theme.bg, location: 0),
                .init(color: theme.bg.opacity(0.9), location: 0.45),
                .init(color: theme.bg.opacity(0), location: 1),
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private var content: some View {
        HStack(alignment: .bottom, spacing: 28) {
            posterCard
                .frame(width: 200, height: 300)

            VStack(alignment: .leading, spacing: 0) {
                chipsRow
                    .padding(.bottom, 12)
                romajiLine
                    .padding(.bottom, 6)
                titleText
                    .padding(.bottom, 16)
                metaRow
                    .padding(.bottom, 20)
                actionsRow
            }
            .padding(.bottom, 10)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
        .padding(.top, 80)
        .padding(.bottom, 28)
        .frame(maxWidth: 1440, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pieces

    private var posterCard: some View {
        Group {
            if let url = heroURL {
                CachedRemoteImage(
                    url: url,
                    contentMode: .fill,
                    placeholder: { theme.bg2 },
                    failure: { theme.bg2 }
                )
            } else {
                theme.bg2
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 20, x: 0, y: 20)
    }

    @ViewBuilder
    private var chipsRow: some View {
        HStack(spacing: 8) {
            if let status = vm.detail?.status, !status.isEmpty {
                DSChip(title: statusLabel(status), isActive: true, size: .small, mono: true)
            }
            if let season = seasonLabel {
                DSChip(title: season, size: .small, mono: true)
            }
            if let rating = vm.detail?.rating, !rating.isEmpty {
                DSChip(title: ratingLabel(rating), size: .small, mono: true)
            }
        }
    }

    @ViewBuilder
    private var romajiLine: some View {
        if !vm.romajiTitle.isEmpty {
            Text(vm.romajiTitle)
                .font(.dsMono(12, weight: .medium))
                .tracking(2)
                .foregroundStyle(theme.fg3)
        }
    }

    private var titleText: some View {
        Text(vm.title)
            .font(.dsDisplay(56, weight: .heavy))
            .tracking(-1.5)
            .foregroundStyle(theme.fg)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 800, alignment: .leading)
    }

    @ViewBuilder
    private var metaRow: some View {
        HStack(spacing: 14) {
            if let score = vm.detail?.score, !score.isEmpty, score != "0.0", score != "0" {
                HStack(spacing: 4) {
                    DSIcon(name: .star, size: 15, weight: .bold)
                        .foregroundStyle(scoreColor(Double(score) ?? 0))
                    Text(score)
                        .font(.dsMono(14, weight: .bold))
                        .foregroundStyle(scoreColor(Double(score) ?? 0))
                }
            }
            Text("·").foregroundStyle(theme.fg3)
            Text("**\(vm.episodeCount)** эпизодов")
                .font(.dsBody(14))
                .foregroundStyle(theme.fg2)
            if let duration = vm.detail?.duration, duration > 0 {
                Text("·").foregroundStyle(theme.fg3)
                Text("**\(duration)** мин")
                    .font(.dsBody(14))
                    .foregroundStyle(theme.fg2)
            }
            if let genresString, !genresString.isEmpty {
                Text("·").foregroundStyle(theme.fg3)
                Text(genresString)
                    .font(.dsBody(14))
                    .foregroundStyle(theme.fg2)
                    .lineLimit(1)
            }
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            // Announcement titles have not aired yet — hide player and dub
            // picker, keep only status (e.g. "Planned"), favorites, and links.
            if !vm.isAnons {
                DSButton(
                    vm.isPreparingPlayback
                        ? "Открываем эпизод \(vm.nextEpisodeToWatch)…"
                        : "Смотреть эпизод \(vm.nextEpisodeToWatch)",
                    variant: .primary,
                    size: .large,
                    icon: .play,
                    isLoading: vm.isPreparingPlayback,
                    action: onWatch
                )
            }

            statusButton

            if !vm.isAnons {
                studioButton
            }

            iconButton(name: .heart, active: vm.isFavorite, disabled: vm.isUpdatingFavorite, help: vm.isFavorite ? "Убрать из избранного" : "В избранное", action: onToggleFavorite)

            iconButton(
                name: linkCopiedFlash ? .check : .link,
                active: linkCopiedFlash,
                disabled: false,
                help: "Скопировать ссылку на тайтл",
                action: onCopyLink
            )

            iconButton(name: .safari, active: false, disabled: false, help: "Открыть на Shikimori в браузере", action: onOpenOnShikimori)
        }
    }

    private func iconButton(name: DSIconName, active: Bool, disabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DSIcon(name: name, size: 18, weight: active ? .bold : .medium)
                .foregroundStyle(active ? theme.accent : theme.fg2)
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(active ? theme.accent : theme.line2, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    // MARK: - Helpers

    private var heroURL: URL? {
        // Take from the VM: it already prefers GraphQL (canonical URLs),
        // falls back to REST, and filters out missing_preview.
        // WARNING: no logUIEvent here — this computed property is called from
        // body (backdrop + posterCard), and publishing into NetworkLogStore
        // triggers "Publishing changes from within view updates" -> freeze.
        vm.posterURL
    }

    private var seasonLabel: String? {
        guard let raw = vm.detail?.airedOn ?? vm.detail?.releasedOn, raw.count >= 4 else { return nil }
        return String(raw.prefix(4))
    }

    private var genresString: String? {
        let names = (vm.detail?.genres ?? []).compactMap { $0.russian ?? $0.name }
        guard !names.isEmpty else { return nil }
        return names.prefix(3).joined(separator: " · ")
    }

    private func statusLabel(_ raw: String) -> String {
        switch raw {
        case "ongoing":  return "Онгоинг"
        case "released": return "Вышло"
        case "anons":    return "Анонс"
        case "latest":   return "Недавно"
        default:         return raw.capitalized
        }
    }

    private func ratingLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "g":       return "G"
        case "pg":      return "PG"
        case "pg_13":   return "PG-13"
        case "r":       return "R-17"
        case "r_plus":  return "R+"
        case "rx":      return "Rx"
        default:        return raw.uppercased()
        }
    }

    private func scoreColor(_ value: Double) -> Color {
        if value >= 9 { return theme.accent }
        if value >= 8 { return theme.warn }
        if value >= 7 { return theme.good }
        return theme.fg2
    }

}
