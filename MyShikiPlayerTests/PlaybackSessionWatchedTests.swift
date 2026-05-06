//
//  PlaybackSessionWatchedTests.swift
//  MyShikiPlayerTests
//
//  Pure-logic checks for `PlaybackSession.reportWatchedIfSufficient`. The
//  threshold semantics and per-episode idempotency are the safety net the
//  upcoming Phase-5 mutation extraction will rely on, so we cover them
//  before any callsite moves.
//

import Foundation
import Testing
@testable import MyShikiPlayer

@MainActor
@Suite("PlaybackSession.reportWatchedIfSufficient")
struct PlaybackSessionReportWatchedTests {
    /// A session detached from the live registry so we don't accidentally
    /// touch network. We also use a brand-new `WatchProgressStore` (UserDefaults-
    /// backed but namespaced by key, not session) — `currentShikimoriId` stays
    /// nil unless a test explicitly drives `prepare`, so `markCompleted` is a
    /// no-op for these unit tests.
    private static func makeSession() -> PlaybackSession {
        PlaybackSession(
            sourceRegistry: SourceRegistry(adapters: [:]),
            progressStore: WatchProgressStore()
        )
    }

    @Test func belowThresholdDoesNotFire() {
        let session = Self.makeSession()
        var fired: [Int] = []
        session.onEpisodeWatched = { fired.append($0) }
        session.watchedThreshold = 0.85

        // 50% < 85% → no callback.
        session.reportWatchedIfSufficient(episode: 1, position: 100, duration: 200)
        #expect(fired.isEmpty)
    }

    @Test func atOrAboveThresholdFiresOnce() {
        let session = Self.makeSession()
        var fired: [Int] = []
        session.onEpisodeWatched = { fired.append($0) }
        session.watchedThreshold = 0.85

        // 85% exactly — must fire (>=).
        session.reportWatchedIfSufficient(episode: 1, position: 170, duration: 200)
        #expect(fired == [1])

        // Repeated calls for the same episode must NOT fire again.
        session.reportWatchedIfSufficient(episode: 1, position: 180, duration: 200)
        session.reportWatchedIfSufficient(episode: 1, position: 199, duration: 200)
        #expect(fired == [1])
    }

    @Test func differentEpisodesEachFireOnce() {
        let session = Self.makeSession()
        var fired: [Int] = []
        session.onEpisodeWatched = { fired.append($0) }
        session.watchedThreshold = 0.85

        session.reportWatchedIfSufficient(episode: 1, position: 180, duration: 200)
        session.reportWatchedIfSufficient(episode: 2, position: 180, duration: 200)
        session.reportWatchedIfSufficient(episode: 2, position: 199, duration: 200) // ignored
        session.reportWatchedIfSufficient(episode: 3, position: 180, duration: 200)
        #expect(fired == [1, 2, 3])
    }

    @Test func zeroDurationOrPositionGuardsTriggerEarly() {
        let session = Self.makeSession()
        var fired: [Int] = []
        session.onEpisodeWatched = { fired.append($0) }

        session.reportWatchedIfSufficient(episode: 1, position: 100, duration: 0)
        session.reportWatchedIfSufficient(episode: 1, position: 0, duration: 200)
        session.reportWatchedIfSufficient(episode: 0, position: 100, duration: 200) // episode < 1
        #expect(fired.isEmpty)
    }

    @Test func customThresholdRespected() {
        let session = Self.makeSession()
        var fired: [Int] = []
        session.onEpisodeWatched = { fired.append($0) }

        // Override threshold to 50%.
        session.watchedThreshold = 0.5
        session.reportWatchedIfSufficient(episode: 1, position: 100, duration: 200)
        #expect(fired == [1])

        // 49% — below threshold, must not fire.
        session.reportWatchedIfSufficient(episode: 2, position: 98, duration: 200)
        #expect(fired == [1])
    }
}
