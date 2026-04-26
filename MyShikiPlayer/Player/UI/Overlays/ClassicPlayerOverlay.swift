//
//  ClassicPlayerOverlay.swift
//  MyShikiPlayer
//
//  New player overlay (variant A from screens-player.jsx):
//  top bar + central play icon (on pause) + skip-intro/next-ep (floating)
//  + label-row (when chapters exist) + scrub + bottom bar.
//
//  Knows nothing about NSWindow — visibility is managed by the parent PlayerView via isVisible.
//

import SwiftUI

struct ClassicPlayerOverlay: View {
    @ObservedObject var session: PlaybackSession
    @ObservedObject var engine: PlayerEngine

    let isVisible: Bool
    let isAlwaysOnTop: Bool
    let onRequestClose: () -> Void
    let onToggleAlwaysOnTop: () -> Void

    private let accent = Color(hex: 0xFF4D5E) // player always uses midnight-accent

    private var selectedSource: PlaybackSession.MediaSource? { session.selectedSource }
    private var episode: Int { selectedSource?.episode ?? 1 }
    private var title: String { selectedSource?.title ?? "Плеер" }

    private var chapters: [PlayerChapter] {
        PlayerChapterFactory.chapters(
            duration: engine.duration,
            opening: session.currentOpeningRangeSeconds,
            ending: session.currentEndingRangeSeconds
        )
    }

    /// Active skip range under the playhead: opening wins over ending when
    /// both somehow overlap. Nil means the floating button must stay hidden.
    private var activeSkipRange: (range: ClosedRange<Double>, kind: PlayerChapter.Kind)? {
        let now = engine.currentTime
        if let opening = session.currentOpeningRangeSeconds, opening.contains(now) {
            return (opening, .opening)
        }
        if let ending = session.currentEndingRangeSeconds, ending.contains(now) {
            return (ending, .ending)
        }
        return nil
    }

    private var skipLabel: String {
        switch activeSkipRange?.kind {
        case .ending:
            return "Пропустить эндинг"
        default:
            return "Пропустить опенинг"
        }
    }

    private var remainingSeconds: Double {
        max(0, engine.duration - engine.currentTime)
    }

    private var shouldShowNextEpisodeCard: Bool {
        guard session.canSelectNextEpisode else { return false }
        guard engine.duration > 0 else { return false }
        return remainingSeconds <= 30 && remainingSeconds > 0
    }

    var body: some View {
        ZStack {
            backgroundGradients
                .opacity(isVisible ? 1 : 0)

            VStack(spacing: 0) {
                PlayerTopBar(
                    episodeNumber: episode,
                    title: title,
                    isAlwaysOnTop: isAlwaysOnTop,
                    onBack: onRequestClose,
                    onToggleAlwaysOnTop: onToggleAlwaysOnTop
                )

                fallbackHintBanner

                Spacer()

                bottomControlsContainer
            }
            .opacity(isVisible ? 1 : 0)

            // Central play indicator — only when paused
            if !engine.isPlaying && !engine.isBuffering {
                CenterPlayButton()
                    .transition(.opacity)
            }

            floatingCards
        }
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .animation(.easeInOut(duration: 0.2), value: engine.isPlaying)
    }

    // MARK: - Layers

    /// Fixed-height container so the appearance/disappearance of the hint
    /// never shifts the surrounding layout (feedback_ui_stability). The text
    /// is driven by `session.fallbackHint`, which the session sets/clears
    /// from non-render code paths only.
    private var fallbackHintBanner: some View {
        HStack {
            Spacer(minLength: 0)
            Text(session.fallbackHint ?? " ")
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.55))
                )
                .opacity(session.fallbackHint == nil ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: session.fallbackHint)
            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .padding(.top, 8)
        .allowsHitTesting(false)
    }

    private var backgroundGradients: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(0.35), Color.black.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            Spacer()
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
        }
        .allowsHitTesting(false)
    }

    private var bottomControlsContainer: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChapterScrubBar(
                chapters: chapters,
                duration: engine.duration,
                currentTime: engine.currentTime,
                accent: accent,
                onSeek: { engine.seek(seconds: $0) }
            )

            PlayerBottomBar(
                session: session,
                engine: engine,
                accent: accent,
                onToggleFullscreen: { engine.togglePlayerWindowFullScreen() }
            )
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
    }

    private var floatingCards: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                VStack(alignment: .trailing, spacing: 14) {
                    if shouldShowNextEpisodeCard {
                        NextEpisodeCard(
                            nextEpisodeNumber: episode + 1,
                            remainingSeconds: remainingSeconds,
                            accent: accent,
                            onPlayNext: {
                                Task { await session.selectNextEpisodeAndLoad() }
                            }
                        )
                    }
                    if activeSkipRange != nil {
                        SkipIntroButton(label: skipLabel, action: skipIntroAction)
                    }
                }
                .padding(.trailing, 28)
                .padding(.bottom, 170)
                .opacity(isVisible ? 1 : 0)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomTrailing)
        }
        .allowsHitTesting(isVisible)
    }

    private func skipIntroAction() {
        guard let active = activeSkipRange else { return }
        let target = min(active.range.upperBound, max(engine.duration - 1, 0))
        engine.seek(seconds: target)
    }
}
