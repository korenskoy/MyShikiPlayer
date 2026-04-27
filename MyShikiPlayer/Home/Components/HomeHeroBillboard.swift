//
//  HomeHeroBillboard.swift
//  MyShikiPlayer
//
//  Large hero block on Home: blurred/dimmed title image on the left →
//  gradient to the right, text on top-left — status badge, romaji,
//  large heading, meta, description, buttons.
//

import SwiftUI

struct HomeHeroBillboard: View {
    @Environment(\.appTheme) private var theme
    let item: AnimeListItem
    let onWatch: () -> Void
    let onOpenDetails: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            backdrop
            gradient
            content
        }
        .frame(height: 360)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
    }

    // MARK: - Layers

    private var backdrop: some View {
        Group {
            if let url = posterURL {
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
                .init(color: theme.bg.opacity(0.93), location: 0.35),
                .init(color: theme.bg.opacity(0), location: 0.75),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text("СЕЙЧАС В ЭФИРЕ")
                    .font(.dsLabel(10, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(theme.mode == .dark ? Color(hex: 0x0B0A0D) : Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(theme.accent)
                    )
                Text(romajiLine)
                    .font(.dsMono(11))
                    .tracking(1)
                    .foregroundStyle(theme.fg3)
            }

            Text(title)
                .font(.dsDisplay(48, weight: .heavy))
                .tracking(-1)
                .foregroundStyle(theme.fg)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                if let value = scoreValue {
                    HStack(spacing: 4) {
                        DSIcon(name: .star, size: 14, weight: .bold)
                        Text(String(format: "%.2f", value))
                            .font(.dsMono(14, weight: .semibold))
                    }
                    .foregroundStyle(scoreColor(value))
                    Text("·").foregroundStyle(theme.fg3)
                }
                if let episodes = item.episodes, episodes > 0 {
                    Text("\(episodes) эп")
                        .font(.dsBody(13))
                        .foregroundStyle(theme.fg2)
                }
            }

            HStack(spacing: 10) {
                DSButton(
                    "Смотреть",
                    variant: .primary,
                    size: .large,
                    icon: .play,
                    action: onWatch
                )
                DSButton(
                    "Подробнее",
                    variant: .secondary,
                    size: .large,
                    icon: .info,
                    action: onOpenDetails
                )
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
        .frame(maxWidth: 680, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    private var scoreValue: Double? {
        guard let raw = item.score, !raw.isEmpty, raw != "0.0", raw != "0" else { return nil }
        return Double(raw)
    }

    private func scoreColor(_ value: Double) -> Color {
        if value >= 9 { return theme.accent }
        if value >= 8 { return theme.warn }
        if value >= 7 { return theme.good }
        return theme.fg2
    }

    private var title: String {
        if let r = item.russian, !r.isEmpty { return r }
        return item.name
    }

    private var romajiLine: String {
        let year = (item.releasedOn ?? item.airedOn).flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil } ?? ""
        return [item.name, year].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var posterURL: URL? {
        let raw = item.image?.original ?? item.image?.preview ?? item.image?.x96
        guard let raw, !raw.isEmpty, !raw.contains("missing_preview"), !raw.contains("missing_original") else { return nil }
        if raw.hasPrefix("http") { return URL(string: raw) }
        if raw.hasPrefix("/") { return ShikimoriURL.media(path: raw) }
        return URL(string: raw)
    }
}
