//
//  WatchProgressStore.swift
//  MyShikiPlayer
//

import Foundation
import Combine

@MainActor
final class WatchProgressStore: ObservableObject {
    struct ProgressRecord: Codable {
        let shikimoriId: Int
        let episode: Int
        let seconds: Double
        let updatedAt: Date
    }

    @Published private(set) var recordsByTitle: [Int: ProgressRecord] = [:]

    private let defaultsKey = "watchProgressStore.records"

    init() {
        restore()
        // Allow centralised wipes (sign-out / requires-reauth) to drop in-memory
        // resume positions without juggling shared instances. PersonalCacheCleaner
        // already removes the UserDefaults blob; this listener flushes RAM too.
        CacheEvents.observeClearAll { [weak self] in
            self?.purgeInMemoryRecords()
        }
    }

    private func purgeInMemoryRecords() {
        guard !recordsByTitle.isEmpty else { return }
        recordsByTitle.removeAll()
    }

    func save(shikimoriId: Int, episode: Int, seconds: Double) {
        recordsByTitle[shikimoriId] = ProgressRecord(
            shikimoriId: shikimoriId,
            episode: episode,
            seconds: seconds,
            updatedAt: Date()
        )
        persist()
    }

    func progress(shikimoriId: Int) -> ProgressRecord? {
        recordsByTitle[shikimoriId]
    }

    /// Returns resume seconds only if the latest record matches the
    /// requested episode. When the user opens a different episode,
    /// continuing from another position makes no sense.
    func resumeSeconds(shikimoriId: Int, episode: Int) -> Double? {
        guard let record = recordsByTitle[shikimoriId], record.episode == episode else {
            return nil
        }
        return record.seconds
    }

    /// Clears the record if it points at the given episode. Called when
    /// the episode is marked as watched — resuming near the end is no
    /// longer needed; the user is moving on.
    func clearIfMatches(shikimoriId: Int, episode: Int) {
        guard let record = recordsByTitle[shikimoriId], record.episode == episode else { return }
        recordsByTitle.removeValue(forKey: shikimoriId)
        persist()
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        guard let decoded = try? JSONDecoder().decode([Int: ProgressRecord].self, from: data) else { return }
        recordsByTitle = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(recordsByTitle) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
