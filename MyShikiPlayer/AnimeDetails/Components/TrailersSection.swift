//
//  TrailersSection.swift
//  MyShikiPlayer
//
//  Trailer/clip cards. Shikimori returns url (usually YouTube), name, and
//  kind (pv / op / ed / cm). Click opens the url in the browser — the macOS
//  player handles YouTube embedding poorly, and embedding is not needed.
//

import AppKit
import SwiftUI

struct TrailersSection: View {
    @Environment(\.appTheme) private var theme
    let videos: [AnimeVideoREST]

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
        count: 5
    )

    private var filtered: [AnimeVideoREST] {
        videos.filter { v in
            guard let kind = v.kind?.lowercased() else { return true }
            // Filter out "noise" kinds (clip/character/etc) — keep pv/op/ed/cm.
            return ["pv", "op", "ed", "cm", "trailer", "promo"].contains(kind)
        }
    }

    var body: some View {
        if filtered.isEmpty {
            EmptyView()
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(Array(filtered.prefix(10).enumerated()), id: \.offset) { _, video in
                    card(for: video)
                }
            }
        }
    }

    private func card(for video: AnimeVideoREST) -> some View {
        Button {
            open(video)
        } label: {
            ZStack(alignment: .bottomLeading) {
                thumbnail(for: video)

                VStack {
                    Spacer()
                    DSIcon(name: .play, size: 22, weight: .bold)
                        .foregroundStyle(Color.white)
                        .padding(10)
                        .background(Circle().fill(theme.accent))
                    Spacer()
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 2) {
                    Text(kindLabel(video.kind))
                        .dsMonoLabel(size: 9, tracking: 1.4)
                        .foregroundStyle(Color.white.opacity(0.8))
                    if let name = video.name, !name.isEmpty {
                        Text(name)
                            .font(.dsBody(11, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.7), Color.black.opacity(0)],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
            }
            .aspectRatio(16.0/9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(theme.line, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func thumbnail(for video: AnimeVideoREST) -> some View {
        // Shikimori returns the YouTube `hqdefault.jpg` over plain HTTP — force
        // HTTPS so ATS allows it. The placeholder/failure surface keeps the
        // card visually stable while the image loads.
        if let url = video.imageUrl?.upgradedToHTTPS {
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

    private func open(_ video: AnimeVideoREST) {
        guard let raw = video.url, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    private func kindLabel(_ kind: String?) -> String {
        switch kind?.lowercased() {
        case "pv":    return "PV"
        case "op":    return "OP"
        case "ed":    return "ED"
        case "cm":    return "CM"
        case "trailer", "promo": return "TRAILER"
        default:      return (kind ?? "VIDEO").uppercased()
        }
    }
}
