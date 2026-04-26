//
//  ResumeCoordinator.swift
//  MyShikiPlayer
//
//  Owns persistence of playback progress: `WatchProgressStore` for the
//  resume-position cache and `WatchHistoryStore` for the user-facing
//  history feed. PlaybackSession delegates to it so the facade stays
//  focused on state and orchestration.
//
//  Phase 4 split. Public surface intentionally tiny — anything that
//  needs to mutate engine / @Published state stays in PlaybackSession.
//

import Foundation

@MainActor
final class ResumeCoordinator {
    let progressStore: WatchProgressStore
    private let historyStore: WatchHistoryStore

    init(
        progressStore: WatchProgressStore,
        historyStore: WatchHistoryStore = .shared
    ) {
        self.progressStore = progressStore
        self.historyStore = historyStore
    }

    /// Returns the saved resume position for the given title+episode, if any.
    /// Callers (PlaybackSession.loadSelectedSource) check it after `load(url:)`
    /// and feed the engine via `engine.seek(seconds:)`.
    func resumeSeconds(shikimoriId: Int, episode: Int) -> TimeInterval? {
        progressStore.resumeSeconds(shikimoriId: shikimoriId, episode: episode)
    }

    /// Records that the user just opened an episode (used by the history
    /// feed to surface "watch in progress" entries even before any
    /// position update).
    func recordStarted(shikimoriId: Int, episode: Int, title: String) {
        historyStore.recordStarted(
            shikimoriId: shikimoriId,
            episode: episode,
            title: title,
            position: 0,
            duration: 0
        )
    }

    /// Persists the live position both to the resume cache and the history
    /// feed. Called from PlaybackSession.saveProgressSnapshot during normal
    /// playback ticks and on player close.
    func recordProgress(
        shikimoriId: Int,
        episode: Int,
        title: String,
        position: Double,
        duration: Double
    ) {
        progressStore.save(
            shikimoriId: shikimoriId,
            episode: episode,
            seconds: position
        )
        historyStore.recordProgress(
            shikimoriId: shikimoriId,
            episode: episode,
            title: title,
            position: position,
            duration: duration
        )
    }

    /// Saves only the resume position (without touching the history feed).
    /// Used during episode-jumps where the leaving episode's position must
    /// survive even though the user did not "watch" it.
    func saveResumePoint(
        shikimoriId: Int,
        episode: Int,
        position: Double
    ) {
        guard position > 1 else { return }
        progressStore.save(
            shikimoriId: shikimoriId,
            episode: episode,
            seconds: position
        )
    }

    /// Marks the episode as completed in the history feed and clears the
    /// resume cache so reopening the episode starts from the beginning
    /// (otherwise it would resume at ~90% and skip the intro).
    func markCompleted(
        shikimoriId: Int,
        episode: Int,
        title: String,
        position: Double,
        duration: Double
    ) {
        historyStore.recordCompleted(
            shikimoriId: shikimoriId,
            episode: episode,
            title: title,
            position: position,
            duration: duration
        )
        progressStore.clearIfMatches(shikimoriId: shikimoriId, episode: episode)
    }
}
