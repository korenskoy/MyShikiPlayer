//
//  HistoryMergerTests.swift
//  MyShikiPlayerTests
//

import XCTest
@testable import MyShikiPlayer

final class HistoryMergerTests: XCTestCase {

    // MARK: - Local collapse

    func test_collapseLocal_collapsesSameEpisodeSameDayToSingleItem() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 12))!
        let events: [WatchHistoryStore.Event] = [
            makeLocal(shikimoriId: 1, episode: 3, action: .started, at: day),
            makeLocal(shikimoriId: 1, episode: 3, action: .progress, at: day.addingTimeInterval(60)),
            makeLocal(shikimoriId: 1, episode: 3, action: .progress, at: day.addingTimeInterval(120)),
            makeLocal(shikimoriId: 1, episode: 3, action: .completed, at: day.addingTimeInterval(180)),
        ]

        let merged = HistoryMerger.merge(local: events, remote: [])

        XCTAssertEqual(merged.count, 1)
        if case let .local(action, ids) = merged[0].source {
            XCTAssertEqual(action, .completed) // most advanced wins
            XCTAssertEqual(ids.count, 4)
        } else {
            XCTFail("Expected local source")
        }
    }

    func test_collapseLocal_keepsDifferentEpisodesSeparate() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 12))!
        let events: [WatchHistoryStore.Event] = [
            makeLocal(shikimoriId: 1, episode: 3, action: .completed, at: day),
            makeLocal(shikimoriId: 1, episode: 4, action: .completed, at: day.addingTimeInterval(600)),
        ]

        let merged = HistoryMerger.merge(local: events, remote: [])

        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(Set(merged.compactMap(\.episode)), [3, 4])
    }

    func test_collapseLocal_separatesRewatchOnDifferentDay() {
        let day1 = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 24, hour: 22))!
        let day2 = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 10))!
        let events: [WatchHistoryStore.Event] = [
            makeLocal(shikimoriId: 1, episode: 3, action: .completed, at: day1),
            makeLocal(shikimoriId: 1, episode: 3, action: .completed, at: day2),
        ]

        let merged = HistoryMerger.merge(local: events, remote: [])

        XCTAssertEqual(merged.count, 2, "Re-watch on a new day must show as a separate row")
    }

    // MARK: - Dedup local vs remote

    func test_merge_dropsRemoteWhenLocalCoversSameEpisodeWithinWindow() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 12))!
        let local = [makeLocal(shikimoriId: 42, episode: 5, action: .completed, at: day)]
        let remote = [makeRemote(targetId: 42, description: "Просмотрен 5-й эпизод", at: day.addingTimeInterval(120))]

        let merged = HistoryMerger.merge(local: local, remote: remote)

        XCTAssertEqual(merged.count, 1)
        XCTAssertTrue(merged[0].isLocal, "Local must win on dedup")
    }

    func test_merge_keepsRemoteOutsideWindow() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 12))!
        let local = [makeLocal(shikimoriId: 42, episode: 5, action: .completed, at: day)]
        // 11 минут разницы — за окном 10.
        let remote = [makeRemote(targetId: 42, description: "Просмотрен 5-й эпизод", at: day.addingTimeInterval(11 * 60))]

        let merged = HistoryMerger.merge(local: local, remote: remote)

        XCTAssertEqual(merged.count, 2)
    }

    func test_merge_keepsRemoteWhenEpisodeUnknown() {
        // remote-rate без эпизода (изменение оценки) — дедуп не срабатывает.
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 12))!
        let local = [makeLocal(shikimoriId: 42, episode: 5, action: .completed, at: day)]
        let remote = [makeRemote(targetId: 42, description: "Поставлена оценка 8", at: day.addingTimeInterval(60))]

        let merged = HistoryMerger.merge(local: local, remote: remote)

        XCTAssertEqual(merged.count, 2)
    }

    func test_merge_keepsRemoteForDifferentTitle() {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 4, day: 25, hour: 12))!
        let local = [makeLocal(shikimoriId: 42, episode: 5, action: .completed, at: day)]
        let remote = [makeRemote(targetId: 99, description: "Просмотрен 5-й эпизод", at: day.addingTimeInterval(60))]

        let merged = HistoryMerger.merge(local: local, remote: remote)

        XCTAssertEqual(merged.count, 2)
    }

    // MARK: - Sort

    func test_merge_sortsDescendingByOccurredAt() {
        let now = Date()
        let local: [WatchHistoryStore.Event] = [
            makeLocal(shikimoriId: 1, episode: 1, action: .completed, at: now.addingTimeInterval(-3600)),
        ]
        let remote: [UserHistoryEntry] = [
            makeRemote(targetId: 2, description: "Поставлена оценка 7", at: now),
            makeRemote(targetId: 3, description: "Поставлена оценка 9", at: now.addingTimeInterval(-7200)),
        ]

        let merged = HistoryMerger.merge(local: local, remote: remote)

        XCTAssertEqual(merged.map(\.shikimoriId), [2, 1, 3])
    }

    // MARK: - extractEpisode

    func test_extractEpisode_handlesCommonRussianForms() {
        XCTAssertEqual(HistoryMerger.extractEpisode(from: "Просмотрен 3-й эпизод"), 3)
        XCTAssertEqual(HistoryMerger.extractEpisode(from: "Просмотрено 12 эпизодов"), 12)
        XCTAssertEqual(HistoryMerger.extractEpisode(from: "Эпизод 5"), 5)
        XCTAssertEqual(HistoryMerger.extractEpisode(from: "Поставлена оценка 8"), nil)
        XCTAssertEqual(HistoryMerger.extractEpisode(from: "Изменён статус на «Просмотрено»"), nil)
    }

    // MARK: - Helpers

    private func makeLocal(
        shikimoriId: Int,
        episode: Int,
        action: WatchHistoryStore.Action,
        at date: Date
    ) -> WatchHistoryStore.Event {
        WatchHistoryStore.Event(
            id: UUID(),
            shikimoriId: shikimoriId,
            episode: episode,
            title: "Test \(shikimoriId)",
            action: action,
            position: 100,
            duration: 1400,
            occurredAt: date
        )
    }

    private func makeRemote(
        targetId: Int,
        description: String,
        at date: Date
    ) -> UserHistoryEntry {
        UserHistoryEntry(
            id: Int.random(in: 1...1_000_000),
            createdAt: date,
            description: description,
            target: HistoryTarget(
                id: targetId,
                name: "Title \(targetId)",
                russian: "Тайтл \(targetId)",
                image: nil,
                url: nil,
                kind: "tv",
                score: nil,
                status: nil,
                episodes: nil,
                episodesAired: nil,
                airedOn: nil,
                releasedOn: nil
            )
        )
    }
}
