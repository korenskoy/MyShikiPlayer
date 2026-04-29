//
//  RailPosterCTA.swift
//  MyShikiPlayer
//
//  Sidebar rail card surfacing the linked anime as a tall poster + title +
//  score chip. Tap opens the anime details screen via the `onOpen` callback.
//

import SwiftUI

struct RailPosterCTA: View {
    @Environment(\.appTheme) private var theme
    let linked: TopicLinked
    let onOpen: (Int) -> Void

    var body: some View {
        Button {
            if let id = linked.id { onOpen(id) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                if let url = posterURL {
                    CachedRemoteImage(
                        url: url,
                        contentMode: .fill,
                        placeholder: { theme.bg2 },
                        failure: { theme.bg2 }
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                Text("ОБСУЖДАЕТСЯ ТАЙТЛ")
                    .font(.dsLabel(9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(theme.accent)
                Text(displayTitle)
                    .font(.dsTitle(15, weight: .semibold))
                    .foregroundStyle(theme.fg)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let score = linked.score, !score.isEmpty, score != "0.0" {
                    HStack(spacing: 4) {
                        DSIcon(name: .star, size: 10, weight: .semibold)
                            .foregroundStyle(theme.warn)
                        Text(score)
                            .font(.dsMono(11))
                            .foregroundStyle(theme.fg2)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Открыть страницу аниме")
    }

    private var posterURL: URL? {
        let raw = linked.image?.original
            ?? linked.image?.preview
            ?? linked.image?.x96
            ?? linked.image?.x48
        guard let raw, !raw.isEmpty, !raw.contains("missing_") else { return nil }
        if raw.hasPrefix("http") { return URL(string: raw) }
        if raw.hasPrefix("/") { return ShikimoriURL.media(path: raw) }
        return URL(string: raw)
    }

    private var displayTitle: String {
        if let r = linked.russian, !r.isEmpty { return r }
        return linked.name ?? "—"
    }
}
