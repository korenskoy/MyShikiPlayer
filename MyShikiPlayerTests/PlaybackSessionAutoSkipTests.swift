//
//  PlaybackSessionAutoSkipTests.swift
//  MyShikiPlayerTests
//
//  Guards the "next episode started at the previous one's end" regression:
//  while the engine is between items its ranges already belong to the
//  incoming episode, so an auto-skip evaluated there would be queued and
//  applied to that episode as soon as it becomes ready.
//

import Foundation
import Testing
@testable import MyShikiPlayer

@MainActor
@Suite("PlaybackSession.maybeAutoSkipSection")
struct PlaybackSessionAutoSkipTests {
    private static func makeSession(endingRange: ClosedRange<Double>) -> PlaybackSession {
        UserDefaults.standard.set(true, forKey: SettingsKeys.autoSkipChapters)
        let session = PlaybackSession(
            sourceRegistry: SourceRegistry(adapters: [:]),
            progressStore: WatchProgressStore()
        )
        session.select(source: PlaybackSession.MediaSource(
            provider: .kodik,
            streamURL: URL(string: "https://example.test/stream.m3u8")!,
            qualityLabel: "720p",
            studioLabel: nil,
            studioId: nil,
            openingRangeSeconds: nil,
            endingRangeSeconds: endingRange,
            episode: 4,
            title: "Test"
        ))
        return session
    }

    /// A freshly loaded item has `canStartPlayback == false` until AVFoundation
    /// reports `.readyToPlay`. A position inside the ending range must not fire
    /// there — that is exactly the between-episodes window.
    @Test func doesNotSkipWhileTheEngineIsNotReady() {
        let session = Self.makeSession(endingRange: 1302...1424)

        #expect(session.maybeAutoSkipSection(now: 1422) == false)
    }

    /// The tick that follows `load()` carries 0 — the start of the new
    /// episode, nowhere near its ending range.
    @Test func doesNotSkipAtTheStartOfAnEpisode() {
        let session = Self.makeSession(endingRange: 1302...1424)

        #expect(session.maybeAutoSkipSection(now: 0) == false)
    }
}
