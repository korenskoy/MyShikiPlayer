//
//  EpisodeListPopover.swift
//  MyShikiPlayer
//
//  Popover with the episode list. Uses the real list from PlaybackSession
//  (propagated from AnimeDetailsViewModel.availableEpisodes). When the data
//  is unavailable, falls back to a heuristic range so the UI is not empty.
//

import SwiftUI

struct EpisodeListPopover: View {
    let currentEpisode: Int
    let availableEpisodes: [Int]
    let onSelect: (Int) -> Void

    private var episodeRange: [Int] {
        if !availableEpisodes.isEmpty {
            return availableEpisodes
        }
        let upper = max(currentEpisode + 12, 24)
        return Array(1...upper)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ЭПИЗОДЫ")
                .dsMonoLabel(size: 10, tracking: 1.4)
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(episodeRange, id: \.self) { ep in
                            row(for: ep)
                                .id(ep)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
                .onAppear {
                    proxy.scrollTo(currentEpisode, anchor: .center)
                }
            }
        }
        .frame(width: 280, height: 380)
        .background(Color(hex: 0x141218))
    }

    private func row(for episode: Int) -> some View {
        let selected = episode == currentEpisode
        return Button(action: { onSelect(episode) }) {
            HStack(spacing: 10) {
                Text(String(format: "%02d", episode))
                    .font(.dsMono(11, weight: selected ? .bold : .semibold))
                    .foregroundStyle(selected ? Color(hex: 0xFF4D5E) : Color.white.opacity(0.55))
                    .frame(width: 28, alignment: .leading)

                Text("Эпизод \(episode)")
                    .font(.dsBody(12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)

                if selected {
                    Circle()
                        .fill(Color(hex: 0xFF4D5E))
                        .frame(width: 6, height: 6)
                        .shadow(color: Color(hex: 0xFF4D5E), radius: 4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}
