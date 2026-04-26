//
//  PlayerBottomBar.swift
//  MyShikiPlayer
//
//  Bottom player bar (variant A). Reads data from session/engine; transport
//  controls call engine methods; popover pills call session.select(source:) /
//  session.selectEpisodeAndLoad. SUB/bell/pip/gear were dropped (per user's
//  decision: when data is missing, hide the button).
//

import AppKit
import SwiftUI

struct PlayerBottomBar: View {
    @ObservedObject var session: PlaybackSession
    @ObservedObject var engine: PlayerEngine
    let accent: Color
    let onToggleFullscreen: () -> Void

    @State private var showingDub = false
    @State private var showingQuality = false
    @State private var showingSpeed = false
    @State private var showingEpisodes = false

    private static let speedOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.4, 1.5, 1.75, 2.0]

    private var currentSource: PlaybackSession.MediaSource? { session.selectedSource }

    private var currentEpisode: Int { currentSource?.episode ?? 1 }

    /// Grouping key for the "DUB" pill: translation studio, or provider as a fallback.
    private func dubKey(for source: PlaybackSession.MediaSource) -> String {
        let trimmed = source.studioLabel?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? source.provider.rawValue.capitalized : trimmed
    }

    private var dubOptions: [StudioOption] {
        // The DUB picker reads from `availableStudios` — those are the studios
        // the source catalog knows about, including the ones we have not
        // resolved yet. Resolution happens lazily inside `selectStudioAndLoad`
        // when the user taps an entry.
        session.availableStudios
    }

    private func qualityOptions(for studioId: Int?) -> [PlaybackSession.MediaSource] {
        // Qualities of the current studio. Fall back to provider if studio is
        // missing (single-source providers may not expose a studioId).
        guard let current = currentSource else { return [] }
        var seen = Set<String>()
        return session.availableSources.filter { src in
            let matches: Bool
            if let studioId, src.studioId == studioId {
                matches = true
            } else if studioId == nil, src.provider == current.provider, src.studioId == current.studioId {
                matches = true
            } else {
                matches = false
            }
            guard matches, !seen.contains(src.qualityLabel) else { return false }
            seen.insert(src.qualityLabel)
            return true
        }
    }

    private var dubValueText: String {
        guard let current = currentSource else { return "—" }
        return dubKey(for: current)
    }

    private var qualityValueText: String {
        currentSource?.qualityLabel ?? "—"
    }

    private var speedValueText: String {
        String(format: "×%g", engine.playbackRate)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            timecode

            DSPlayerIconButton(icon: .skip10Back) {
                engine.seek(delta: -10)
            }
            .help("Назад 10 с (←)")

            playPauseButton

            DSPlayerIconButton(icon: .skip10Forward) {
                engine.seek(delta: 10)
            }
            .help("Вперёд 10 с (→)")

            volumeSlider

            Spacer(minLength: 10)

            dubPill
            qualityPill
            speedPill

            episodesButton
                .help("Список эпизодов")

            DSPlayerIconButton(icon: .full, action: onToggleFullscreen)
                .help("Во весь экран (F)")
        }
    }

    // MARK: - Timecode / transport / volume

    private var timecode: some View {
        HStack(spacing: 4) {
            Text(PlayerTimeFormatter.mmss(engine.currentTime))
                .font(.dsMono(13, weight: .semibold))
                .foregroundStyle(Color.white)
            Text("/ \(PlayerTimeFormatter.mmss(engine.duration))")
                .font(.dsMono(13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }

    private var playPauseButton: some View {
        Button(action: { engine.playOrPause() }) {
            DSIcon(name: engine.isPlaying ? .pause : .play, size: 20, weight: .semibold)
                .foregroundStyle(Color(hex: 0x0B0A0D))
                .frame(width: 52, height: 52)
                .background(Circle().fill(accent))
        }
        .buttonStyle(.plain)
        .help(engine.isPlaying ? "Пауза (Space)" : "Играть (Space)")
    }

    private var volumeSlider: some View {
        HStack(spacing: 8) {
            DSIcon(name: .vol, size: 16, weight: .regular)
                .foregroundStyle(Color.white)

            GeometryReader { geo in
                let clamped = CGFloat(max(0, min(1, engine.volume)))
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.25))
                    Capsule(style: .continuous)
                        .fill(Color.white)
                        .frame(width: geo.size.width * clamped)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = max(0, min(1, value.location.x / geo.size.width))
                            engine.volume = Float(fraction)
                        }
                )
            }
            .frame(width: 90, height: 3)
        }
    }

    // MARK: - Pills & popovers

    private var dubPill: some View {
        DSPlayerPill(label: "ДУБ", value: dubValueText, icon: .mic) {
            showingDub.toggle()
        }
        .disabled(session.resolvingStudioId != nil)
        .popover(isPresented: $showingDub, arrowEdge: .top) {
            PlayerChoiceList(
                header: "ОЗВУЧКА",
                items: dubOptions,
                titleFor: { $0.studioLabel },
                subtitleFor: nil,
                isSelected: { studio in
                    studio.studioId == currentSource?.studioId
                },
                onSelect: { studio in
                    showingDub = false
                    Task { await session.selectStudioAndLoad(studioId: studio.studioId) }
                }
            )
        }
    }

    private var qualityPill: some View {
        DSPlayerPill(label: qualityValueText, value: nil, icon: nil) {
            showingQuality.toggle()
        }
        .popover(isPresented: $showingQuality, arrowEdge: .top) {
            PlayerChoiceList(
                header: "КАЧЕСТВО",
                items: qualityOptions(for: currentSource?.studioId),
                titleFor: { $0.qualityLabel },
                subtitleFor: nil,
                isSelected: { $0.qualityLabel == currentSource?.qualityLabel },
                onSelect: { src in
                    session.select(source: src)
                    session.loadSelectedSource(autoPlay: true)
                    showingQuality = false
                }
            )
        }
    }

    private var speedPill: some View {
        DSPlayerPill(label: speedValueText, value: nil, icon: .speed) {
            showingSpeed.toggle()
        }
        .popover(isPresented: $showingSpeed, arrowEdge: .top) {
            PlayerChoiceList(
                header: "СКОРОСТЬ",
                items: Self.speedOptions,
                titleFor: { String(format: "×%.2f", $0) },
                subtitleFor: nil,
                isSelected: { abs($0 - engine.playbackRate) < 0.001 },
                onSelect: { rate in
                    engine.playbackRate = rate
                    showingSpeed = false
                }
            )
        }
    }

    private var episodesButton: some View {
        DSPlayerIconButton(icon: .list) {
            showingEpisodes.toggle()
        }
        .popover(isPresented: $showingEpisodes, arrowEdge: .top) {
            EpisodeListPopover(
                currentEpisode: currentEpisode,
                availableEpisodes: session.availableEpisodes,
                onSelect: { ep in
                    showingEpisodes = false
                    Task { await session.selectEpisodeAndLoad(ep) }
                }
            )
        }
    }
}
