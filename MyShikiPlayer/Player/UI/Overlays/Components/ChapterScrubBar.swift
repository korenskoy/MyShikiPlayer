//
//  ChapterScrubBar.swift
//  MyShikiPlayer
//
//  Player scrub bar. Draws a single track from 0 to duration, fills progress,
//  draws a thumb, and supports drag-to-seek. Optionally highlights spans of
//  known chapters (e.g. the opening range) — but does NOT split the track
//  into segments unless we have a full chapter map.
//

import SwiftUI

struct ChapterScrubBar: View {
    let chapters: [PlayerChapter]
    let duration: Double
    let currentTime: Double
    let accent: Color

    var onSeek: (Double) -> Void = { _ in }

    @State private var dragFraction: Double? = nil

    private let trackHeight: CGFloat = 5
    private let thumbDiameter: CGFloat = 13

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !chapters.isEmpty {
                labelsRow
            }
            scrubTrack
        }
    }

    private var labelsRow: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ForEach(chapters) { ch in
                    Text(ch.label)
                        .font(.dsLabel(9))
                        .tracking(0.8)
                        .foregroundStyle(Color.white.opacity(0.55))
                        .offset(x: startX(for: ch, width: geo.size.width), y: 0)
                }
            }
        }
        .frame(height: 12)
    }

    private var scrubTrack: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Base
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.3))
                    .frame(height: trackHeight)

                // Highlight known chapters (currently only the opening)
                ForEach(chapters) { ch in
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.45))
                        .frame(
                            width: max(0, widthFor(chapter: ch, total: geo.size.width)),
                            height: trackHeight
                        )
                        .offset(x: startX(for: ch, width: geo.size.width))
                }

                // Progress
                Capsule(style: .continuous)
                    .fill(accent)
                    .frame(
                        width: geo.size.width * effectiveFraction(),
                        height: trackHeight
                    )

                // Thumb
                Circle()
                    .fill(accent)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: accent.opacity(0.25), radius: 6)
                    .offset(x: geo.size.width * effectiveFraction() - thumbDiameter / 2)
            }
            .frame(height: thumbDiameter)
            .contentShape(Rectangle())
            .gesture(dragGesture(in: geo))
        }
        .frame(height: thumbDiameter)
    }

    // MARK: - Geometry helpers

    private func effectiveFraction() -> CGFloat {
        if let dragFraction {
            return CGFloat(dragFraction)
        }
        guard duration > 0 else { return 0 }
        return CGFloat(max(0, min(1, currentTime / duration)))
    }

    private func startX(for chapter: PlayerChapter, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return width * CGFloat(chapter.start / duration)
    }

    private func widthFor(chapter: PlayerChapter, total: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return total * CGFloat(chapter.length / duration)
    }

    private func dragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let fraction = max(0, min(1, value.location.x / geo.size.width))
                dragFraction = fraction
            }
            .onEnded { value in
                let fraction = max(0, min(1, value.location.x / geo.size.width))
                dragFraction = nil
                onSeek(fraction * duration)
            }
    }
}
