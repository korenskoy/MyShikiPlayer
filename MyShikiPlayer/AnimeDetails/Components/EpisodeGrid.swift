//
//  EpisodeGrid.swift
//  MyShikiPlayer
//
//  Two cell rendering modes:
//  - Episode previews exist (kind="episode_preview" in /animes/{id}/videos):
//    3-column grid of cards with YouTube thumbnail and caption.
//  - No previews — compact 8-column grid of numbers (Shikimori-like).
//
//  For long titles (>= `chunkingThreshold` episodes) the grid is split
//  into chunk sections of `chunkSize` episodes. By default the chunk
//  containing the next-to-watch episode is expanded.
//

import SwiftUI

struct EpisodeGrid: View {
    @Environment(\.appTheme) private var theme

    let episodeCount: Int
    let watchedUpTo: Int
    let episodesWithSources: Set<Int>
    /// Episode number → preview image URL (YouTube thumbnail).
    let episodePreviews: [Int: URL]
    /// Episode duration in minutes.
    let episodeDurationMinutes: Int?
    let onTap: (Int) -> Void

    /// Chunk size for long titles.
    private let chunkSize = 40
    /// Episode count threshold to enable grouping.
    private let chunkingThreshold = 60

    /// Which chunk is currently expanded. nil = default (the one with the current episode).
    @State private var expandedChunkOverride: Int?

    var body: some View {
        if shouldChunk {
            chunkedBody
        } else {
            if episodePreviews.isEmpty {
                compactGrid(range: fullRange)
            } else {
                cardGrid(range: fullRange)
            }
        }
    }

    // MARK: - Chunking

    private var fullRange: ClosedRange<Int> { 1...max(1, episodeCount) }
    private var shouldChunk: Bool { episodeCount >= chunkingThreshold }
    private var totalChunks: Int { (episodeCount + chunkSize - 1) / chunkSize }

    private var defaultExpandedChunk: Int {
        let next = min(max(watchedUpTo + 1, 1), episodeCount)
        return (next - 1) / chunkSize
    }

    private var expandedChunk: Int {
        expandedChunkOverride ?? defaultExpandedChunk
    }

    private func chunkRange(_ index: Int) -> ClosedRange<Int> {
        let start = index * chunkSize + 1
        let end = min(start + chunkSize - 1, episodeCount)
        return start...end
    }

    private var chunkedBody: some View {
        VStack(spacing: 8) {
            ForEach(0..<totalChunks, id: \.self) { index in
                chunkSection(index: index)
            }
        }
    }

    @ViewBuilder
    private func chunkSection(index: Int) -> some View {
        let range = chunkRange(index)
        let isExpanded = index == expandedChunk
        let watchedInRange = max(0, min(watchedUpTo, range.upperBound) - (range.lowerBound - 1))
        let hasCurrent = (watchedUpTo + 1) >= range.lowerBound && (watchedUpTo + 1) <= range.upperBound

        VStack(spacing: 0) {
            chunkHeader(
                range: range,
                isExpanded: isExpanded,
                watchedInRange: watchedInRange,
                hasCurrent: hasCurrent
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedChunkOverride = isExpanded ? -1 : index
                }
            }

            if isExpanded {
                Group {
                    if episodePreviews.isEmpty {
                        compactGrid(range: range)
                    } else {
                        cardGrid(range: range)
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(isExpanded ? 12 : 0)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isExpanded ? theme.card.opacity(0.4) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isExpanded ? theme.line : Color.clear, lineWidth: 1)
        )
    }

    private func chunkHeader(
        range: ClosedRange<Int>,
        isExpanded: Bool,
        watchedInRange: Int,
        hasCurrent: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        let total = range.upperBound - range.lowerBound + 1

        return Button(action: onTap) {
            HStack(spacing: 10) {
                DSIcon(name: isExpanded ? .chevD : .chevR, size: 12, weight: .semibold)
                    .foregroundStyle(hasCurrent ? theme.accent : theme.fg2)

                Text("Эпизоды \(range.lowerBound)–\(range.upperBound)")
                    .font(.dsBody(13, weight: hasCurrent ? .bold : .semibold))
                    .foregroundStyle(hasCurrent ? theme.accent : theme.fg)

                Spacer(minLength: 8)

                if hasCurrent {
                    Text("СЕЙЧАС")
                        .font(.dsLabel(9))
                        .tracking(1.4)
                        .foregroundStyle(theme.accent)
                }

                Text("\(watchedInRange)/\(total)")
                    .font(.dsMono(11, weight: .semibold))
                    .foregroundStyle(watchedInRange == total ? theme.good : theme.fg2)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isExpanded ? Color.clear : theme.card.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isExpanded ? Color.clear : theme.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Compact (8-column numbered tiles) — when there are no previews

    private let compactColumns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 8, alignment: .top),
        count: 8
    )

    private func compactGrid(range: ClosedRange<Int>) -> some View {
        LazyVGrid(columns: compactColumns, alignment: .leading, spacing: 8) {
            ForEach(range, id: \.self) { ep in
                compactTile(for: ep)
            }
        }
    }

    private func compactTile(for episode: Int) -> some View {
        let watched = episode <= watchedUpTo
        let available = episodesWithSources.isEmpty || episodesWithSources.contains(episode)
        let current = episode == (watchedUpTo + 1) && available

        return Button {
            guard available else { return }
            onTap(episode)
        } label: {
            VStack(spacing: 4) {
                Text(String(format: "%02d", episode))
                    .font(.dsMono(15, weight: current ? .bold : .semibold))
                    .foregroundStyle(compactForeground(watched: watched, available: available, current: current))
                statusLabel(watched: watched, current: current, available: available)
                if let minutes = episodeDurationMinutes, minutes > 0 {
                    Text("\(minutes) мин")
                        .font(.dsLabel(8))
                        .tracking(0.6)
                        .foregroundStyle(theme.fg3)
                } else {
                    Spacer().frame(height: 10)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(compactBackground(watched: watched, current: current))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(current ? theme.accent : theme.line, lineWidth: 1)
            )
            .opacity(available ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!available)
    }

    @ViewBuilder
    private func statusLabel(watched: Bool, current: Bool, available: Bool) -> some View {
        if watched {
            DSIcon(name: .check, size: 10, weight: .bold)
                .foregroundStyle(theme.good)
        } else if !available {
            Text("нет")
                .font(.dsLabel(8))
                .tracking(1)
                .foregroundStyle(theme.fg3)
        } else if current {
            Text("сейчас")
                .font(.dsLabel(8))
                .tracking(1)
                .foregroundStyle(theme.accent)
        } else {
            Spacer().frame(height: 10)
        }
    }

    private func compactForeground(watched: Bool, available: Bool, current: Bool) -> Color {
        if !available { return theme.fg3 }
        if current    { return theme.accent }
        if watched    { return theme.fg2 }
        return theme.fg
    }

    private func compactBackground(watched: Bool, current: Bool) -> Color {
        if current { return theme.chipBg }
        if watched { return theme.chipBg.opacity(0.5) }
        return theme.card
    }

    // MARK: - Card grid (3-column with thumbnails) — when previews exist

    private let cardColumns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
        count: 3
    )

    private func cardGrid(range: ClosedRange<Int>) -> some View {
        LazyVGrid(columns: cardColumns, alignment: .leading, spacing: 10) {
            ForEach(range, id: \.self) { ep in
                card(for: ep)
            }
        }
    }

    private func card(for episode: Int) -> some View {
        let watched = episode <= watchedUpTo
        let available = episodesWithSources.isEmpty || episodesWithSources.contains(episode)
        let current = episode == (watchedUpTo + 1) && available
        let preview = episodePreviews[episode]

        return Button {
            guard available else { return }
            onTap(episode)
        } label: {
            HStack(spacing: 12) {
                thumbnail(preview: preview, watched: watched, current: current, episode: episode)
                    .frame(width: 100)
                    .aspectRatio(16.0/9.0, contentMode: .fit)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Эпизод \(episode)")
                        .font(.dsBody(13, weight: current ? .bold : .semibold))
                        .foregroundStyle(current ? theme.accent : theme.fg)
                        .lineLimit(1)
                    cardStatusText(watched: watched, current: current, available: available)
                    if let minutes = episodeDurationMinutes, minutes > 0 {
                        Text("\(minutes) мин")
                            .font(.dsMono(10))
                            .foregroundStyle(theme.fg3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 4)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(current ? theme.chipBg : theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(current ? theme.accent : theme.line, lineWidth: 1)
            )
            .opacity(available ? 1 : 0.6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
    }

    @ViewBuilder
    private func cardStatusText(watched: Bool, current: Bool, available: Bool) -> some View {
        if watched {
            Text("ПРОСМОТРЕНО")
                .font(.dsLabel(9))
                .tracking(1.2)
                .foregroundStyle(theme.good)
        } else if current {
            Text("СЕЙЧАС")
                .font(.dsLabel(9))
                .tracking(1.4)
                .foregroundStyle(theme.accent)
        } else if !available {
            Text("НЕТ ИСТОЧНИКА")
                .font(.dsLabel(9))
                .tracking(1.2)
                .foregroundStyle(theme.fg3)
        }
    }

    @ViewBuilder
    private func thumbnail(preview: URL?, watched: Bool, current: Bool, episode: Int) -> some View {
        ZStack {
            if let preview {
                CachedRemoteImage(
                    url: preview,
                    contentMode: .fill,
                    placeholder: { fallbackThumb(episode: episode) },
                    failure: { fallbackThumb(episode: episode) }
                )
            } else {
                fallbackThumb(episode: episode)
            }

            if watched {
                Color.black.opacity(0.55)
                DSIcon(name: .check, size: 22, weight: .bold)
                    .foregroundStyle(Color.white)
            } else if current {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 30, height: 30)
                DSIcon(name: .play, size: 14, weight: .bold)
                    .foregroundStyle(theme.mode == .dark ? Color(hex: 0x0B0A0D) : Color.white)
                    .offset(x: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(theme.line, lineWidth: 0.5)
        )
    }

    private func fallbackThumb(episode: Int) -> some View {
        ZStack {
            theme.bg2
            Text(String(format: "%02d", episode))
                .font(.dsMono(18, weight: .bold))
                .foregroundStyle(theme.fg3)
        }
    }
}
