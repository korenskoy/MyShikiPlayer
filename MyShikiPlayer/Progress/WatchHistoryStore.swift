//
//  WatchHistoryStore.swift
//  MyShikiPlayer
//
//  Append-only watch event journal. Unlike WatchProgressStore
//  (one record per title with the latest position — for resume), this is
//  a CHRONOLOGICAL log: started / progress / completed.
//
//  Persistence — JSON at ~/Library/Caches/MyShikiPlayer/watch-history.json,
//  rotated on overflow (oldest events evicted).
//

import Foundation
import Combine

@MainActor
final class WatchHistoryStore: ObservableObject {
    static let shared = WatchHistoryStore()

    enum Action: String, Codable, Sendable {
        /// Stream found, player started loading — logged once
        /// per prepare() of a specific episode.
        case started
        /// Periodic position snapshot (throttled — no more often than `progressThrottle`).
        case progress
        /// Episode finished (>= watchedThreshold). Once per session.
        case completed
    }

    struct Event: Codable, Sendable, Identifiable, Equatable {
        let id: UUID
        let shikimoriId: Int
        let episode: Int
        let title: String
        let action: Action
        let position: Double
        let duration: Double
        let occurredAt: Date
    }

    @Published private(set) var events: [Event] = []

    private let maxEvents = 500
    private let progressThrottle: TimeInterval = 30
    private let filename = "watch-history.json"

    /// Latest `progress` timestamp per (shikimoriId, episode) — used for throttling.
    private var lastProgressAt: [String: Date] = [:]

    private init() {
        restore()
    }

    // MARK: - Recording

    func recordStarted(shikimoriId: Int, episode: Int, title: String, position: Double, duration: Double) {
        append(Event(
            id: UUID(),
            shikimoriId: shikimoriId,
            episode: episode,
            title: title,
            action: .started,
            position: position,
            duration: duration,
            occurredAt: Date()
        ))
    }

    func recordProgress(shikimoriId: Int, episode: Int, title: String, position: Double, duration: Double) {
        let key = throttleKey(shikimoriId: shikimoriId, episode: episode)
        if let last = lastProgressAt[key], Date().timeIntervalSince(last) < progressThrottle {
            return
        }
        lastProgressAt[key] = Date()
        append(Event(
            id: UUID(),
            shikimoriId: shikimoriId,
            episode: episode,
            title: title,
            action: .progress,
            position: position,
            duration: duration,
            occurredAt: Date()
        ))
    }

    func recordCompleted(shikimoriId: Int, episode: Int, title: String, position: Double, duration: Double) {
        append(Event(
            id: UUID(),
            shikimoriId: shikimoriId,
            episode: episode,
            title: title,
            action: .completed,
            position: position,
            duration: duration,
            occurredAt: Date()
        ))
    }

    // MARK: - Mutations

    func remove(eventId: UUID) {
        guard let idx = events.firstIndex(where: { $0.id == eventId }) else { return }
        events.remove(at: idx)
        persist()
    }

    func clearAll() {
        events.removeAll()
        lastProgressAt.removeAll()
        persist()
    }

    // MARK: - Helpers

    private func throttleKey(shikimoriId: Int, episode: Int) -> String {
        "\(shikimoriId)/\(episode)"
    }

    private func append(_ event: Event) {
        events.append(event)
        if events.count > maxEvents {
            let overflow = events.count - maxEvents
            events.removeFirst(overflow)
        }
        persist()
    }

    // MARK: - Persistence (JSON in caches)

    private func fileURL() -> URL? {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        guard let base else { return nil }
        let dir = base.appendingPathComponent("MyShikiPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    private func persist() {
        guard let url = fileURL() else { return }
        do {
            let data = try JSONEncoder().encode(events)
            try data.write(to: url, options: [.atomic])
        } catch {
            NetworkLogStore.shared.logAppError(
                "watch_history_persist_failed err=\(error.localizedDescription)"
            )
        }
    }

    private func restore() {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url) else { return }
        do {
            let decoded = try JSONDecoder().decode([Event].self, from: data)
            events = decoded
            NetworkLogStore.shared.logUIEvent(
                "watch_history_restored count=\(decoded.count)"
            )
        } catch {
            NetworkLogStore.shared.logAppError(
                "watch_history_restore_failed err=\(error.localizedDescription)"
            )
        }
    }
}
