//
//  PlaybackSessionProgressPersistenceTests.swift
//  MyShikiPlayerTests
//
//  Covers the throttled progress flush that runs off the engine clock: the
//  resume position used to be written only when the player window closed, so a
//  crash mid-episode lost the whole session.
//
//  Every test uses its own shikimoriId — WatchProgressStore is backed by a
//  single shared UserDefaults blob, so records survive between instances and
//  between tests in the same process.
//

import Combine
import Foundation
import Testing
@testable import MyShikiPlayer

@MainActor
@Suite("PlaybackSession progress persistence")
struct PlaybackSessionProgressPersistenceTests {
    /// Session wired to an empty registry: `prepare` resolves nothing and
    /// returns right after setting `currentShikimoriId` / `currentEpisode`,
    /// which is all the persistence paths need — and it never touches network.
    private static func makeSession(
        shikimoriId: Int,
        store: WatchProgressStore,
        now: @escaping () -> Date
    ) async -> PlaybackSession {
        let session = PlaybackSession(
            sourceRegistry: SourceRegistry(adapters: [:]),
            progressStore: store,
            now: now
        )
        await session.prepare(shikimoriId: shikimoriId, title: "Test", episode: 1)
        return session
    }

    @Test func periodicSaveHonoursThrottleInterval() async {
        let shikimoriId = 990_001
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = WatchProgressStore()
        let session = await Self.makeSession(shikimoriId: shikimoriId, store: store, now: { clock })
        session.progressSaveInterval = 15

        var saves = 0
        let observer = store.$recordsByTitle.dropFirst().sink { _ in saves += 1 }
        defer { observer.cancel() }

        session.persistProgressIfDue(position: 100, duration: 1_000)
        #expect(saves == 1)
        #expect(store.resumeSeconds(shikimoriId: shikimoriId, episode: 1) == 100)

        // Inside the window: the position moved, but not enough time passed.
        clock = clock.addingTimeInterval(5)
        session.persistProgressIfDue(position: 120, duration: 1_000)
        clock = clock.addingTimeInterval(5)
        session.persistProgressIfDue(position: 140, duration: 1_000)
        #expect(saves == 1)
        #expect(store.resumeSeconds(shikimoriId: shikimoriId, episode: 1) == 100)

        // Past the interval: flushed again.
        clock = clock.addingTimeInterval(6)
        session.persistProgressIfDue(position: 160, duration: 1_000)
        #expect(saves == 2)
        #expect(store.resumeSeconds(shikimoriId: shikimoriId, episode: 1) == 160)
    }

    @Test func standingStillDoesNotRewriteTheSameRecord() async {
        let shikimoriId = 990_002
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = WatchProgressStore()
        let session = await Self.makeSession(shikimoriId: shikimoriId, store: store, now: { clock })
        session.progressSaveInterval = 15

        var saves = 0
        let observer = store.$recordsByTitle.dropFirst().sink { _ in saves += 1 }
        defer { observer.cancel() }

        session.persistProgressIfDue(position: 200, duration: 1_000)
        #expect(saves == 1)

        // Paused playback: the clock is well past the interval, the position is not.
        clock = clock.addingTimeInterval(120)
        session.persistProgressIfDue(position: 200, duration: 1_000)
        #expect(saves == 1)
    }

    @Test func zeroPositionDoesNotOverwriteSavedPosition() async {
        let shikimoriId = 990_003
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = WatchProgressStore()
        let session = await Self.makeSession(shikimoriId: shikimoriId, store: store, now: { clock })
        session.progressSaveInterval = 15

        session.persistProgressIfDue(position: 300, duration: 1_000)
        #expect(store.resumeSeconds(shikimoriId: shikimoriId, episode: 1) == 300)

        var saves = 0
        let observer = store.$recordsByTitle.dropFirst().sink { _ in saves += 1 }
        defer { observer.cancel() }

        // The engine here reports 0/0 — exactly its state after `stopAndUnload`,
        // which is what PlayerView.onDisappear would hand over on a late save.
        session.saveProgressSnapshot()
        #expect(saves == 0)
        #expect(store.resumeSeconds(shikimoriId: shikimoriId, episode: 1) == 300)

        clock = clock.addingTimeInterval(120)
        session.persistProgressIfDue(position: 0, duration: 0)
        #expect(saves == 0)
        #expect(store.resumeSeconds(shikimoriId: shikimoriId, episode: 1) == 300)
    }

    @Test func watchedIsReportedOnceAcrossManyTicks() async {
        let shikimoriId = 990_004
        var clock = Date(timeIntervalSince1970: 1_000_000)
        let store = WatchProgressStore()
        let session = await Self.makeSession(shikimoriId: shikimoriId, store: store, now: { clock })
        session.progressSaveInterval = 15
        session.watchedThreshold = 0.85

        var fired: [Int] = []
        session.onEpisodeWatched = { fired.append($0) }

        for step in 0..<5 {
            clock = clock.addingTimeInterval(20)
            session.persistProgressIfDue(position: 900 + Double(step * 10), duration: 1_000)
        }

        #expect(fired == [1])
        // `markCompleted` clears the resume point; later ticks must not put it back.
        #expect(store.resumeSeconds(shikimoriId: shikimoriId, episode: 1) == nil)
    }

    @Test func tickDuringPreparationIsIgnored() async {
        let shikimoriId = 990_005
        let clock = Date(timeIntervalSince1970: 1_000_000)
        let store = WatchProgressStore()
        let session = await Self.makeSession(shikimoriId: shikimoriId, store: store, now: { clock })
        session.progressSaveInterval = 15
        session.watchedThreshold = 0.85

        var fired: [Int] = []
        session.onEpisodeWatched = { fired.append($0) }

        // While `prepare` resolves the next episode the engine still reports the
        // previous one's position — attributing it to `currentEpisode` would
        // mark a just-opened episode as watched.
        session.isPreparing = true
        session.persistProgressIfDue(position: 950, duration: 1_000)

        #expect(fired.isEmpty)
        #expect(store.resumeSeconds(shikimoriId: shikimoriId, episode: 1) == nil)
    }
}
