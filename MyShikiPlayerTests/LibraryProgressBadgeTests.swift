//
//  LibraryProgressBadgeTests.swift
//  MyShikiPlayerTests
//

import XCTest
@testable import MyShikiPlayer

/// Covers `AnimeListViewModel.Item.progressBadge` — the "watched / out" chip
/// on library posters. The point of the chip is to flag a newly released
/// episode, so Shikimori's quirky counters must not produce false alarms.
final class LibraryProgressBadgeTests: XCTestCase {

    func testOngoingWithUnwatchedEpisodeIsFlagged() {
        let badge = makeItem(status: "watching", watched: 3, animeStatus: "ongoing", total: 12, aired: 4).progressBadge
        XCTAssertEqual(badge, PosterProgressBadge(text: "3 / 4", hasNew: true))
    }

    func testCaughtUpOngoingIsNotFlagged() {
        let badge = makeItem(status: "watching", watched: 4, animeStatus: "ongoing", total: 0, aired: 4).progressBadge
        XCTAssertEqual(badge, PosterProgressBadge(text: "4 / 4", hasNew: false))
    }

    /// Shikimori reports episodes_aired = 0 for many finished titles.
    func testReleasedTitleUsesTheTotalWhenAiredIsZero() {
        let badge = makeItem(status: "completed", watched: 64, animeStatus: "released", total: 64, aired: 0).progressBadge
        XCTAssertEqual(badge, PosterProgressBadge(text: "64 / 64", hasNew: false))
    }

    /// Only titles the user is following get the "new episode" highlight.
    func testPlannedTitleIsNeverFlagged() {
        let badge = makeItem(status: "planned", watched: 0, animeStatus: "ongoing", total: 12, aired: 5).progressBadge
        XCTAssertEqual(badge, PosterProgressBadge(text: "0 / 5", hasNew: false))
    }

    /// Shikimori's aired counter lags the real release by a few hours.
    func testWatchingAheadOfTheAiredCounterDoesNotOverflow() {
        let badge = makeItem(status: "watching", watched: 6, animeStatus: "ongoing", total: 12, aired: 5).progressBadge
        XCTAssertEqual(badge, PosterProgressBadge(text: "6 / 6", hasNew: false))
    }

    func testNothingOutYieldsNoBadge() {
        XCTAssertNil(makeItem(status: "planned", watched: 0, animeStatus: "anons", total: 12, aired: 0).progressBadge)
    }

    private func makeItem(
        status: String,
        watched: Int,
        animeStatus: String,
        total: Int?,
        aired: Int?
    ) -> AnimeListViewModel.Item {
        AnimeListViewModel.Item(
            id: 1,
            shikimoriId: 100,
            title: "Test",
            kind: "TV",
            year: "2026",
            status: status,
            score: 0,
            episodesWatched: watched,
            posterURL: nil,
            updatedAt: Date(),
            animeStatus: animeStatus,
            animeSeason: nil,
            animeScore: nil,
            animeEpisodes: total,
            animeEpisodesAired: aired
        )
    }
}
