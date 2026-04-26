//
//  ScreenshotsSection.swift
//  MyShikiPlayer
//
//  Screenshots grid styled like "Similar" — 5 columns. Click opens the full
//  image in the browser (or in Preview via NSWorkspace).
//

import AppKit
import SwiftUI

struct ScreenshotsSection: View {
    @Environment(\.appTheme) private var theme
    let screenshots: [AnimeScreenshotREST]
    let onOpen: (Int) -> Void

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
        count: 5
    )

    var body: some View {
        if screenshots.isEmpty {
            EmptyView()
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(Array(screenshots.prefix(10).enumerated()), id: \.offset) { idx, shot in
                    tile(for: shot, at: idx)
                }
            }
        }
    }

    private func tile(for shot: AnimeScreenshotREST, at index: Int) -> some View {
        Button {
            onOpen(index)
        } label: {
            Group {
                if let url = urlFor(raw: shot.preview ?? shot.original) {
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

    static func urlFor(raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        if raw.hasPrefix("/") {
            return ShikimoriURL.media(path: raw)
        }
        return URL(string: raw)
    }

    private func urlFor(raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        if raw.hasPrefix("/") {
            return ShikimoriURL.media(path: raw)
        }
        return URL(string: raw)
    }
}
