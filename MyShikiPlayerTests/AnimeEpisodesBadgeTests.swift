//
//  AnimeEpisodesBadgeTests.swift
//  MyShikiPlayerTests
//

import XCTest
@testable import MyShikiPlayer

/// Covers `AnimeListItem.episodesBadgeText` — the "aired / total" chip on
/// the ongoings cards. Shikimori sends 0 instead of null for missing
/// counters, so both shapes have to collapse to the same result.
final class AnimeEpisodesBadgeTests: XCTestCase {

    func testShowsAiredOverTotalWhenBothKnown() {
        XCTAssertEqual(makeItem(aired: 12, total: 24).episodesBadgeText, "12 / 24")
    }

    func testShowsAiredAloneWhenTotalIsZero() {
        XCTAssertEqual(makeItem(aired: 12, total: 0).episodesBadgeText, "12")
    }

    func testShowsAiredAloneWhenTotalIsMissing() {
        XCTAssertEqual(makeItem(aired: 12, total: nil).episodesBadgeText, "12")
    }

    func testHiddenWhenNothingAired() {
        XCTAssertNil(makeItem(aired: 0, total: 24).episodesBadgeText)
    }

    func testHiddenWhenBothMissing() {
        XCTAssertNil(makeItem(aired: nil, total: nil).episodesBadgeText)
    }

    private func makeItem(aired: Int?, total: Int?) -> AnimeListItem {
        AnimeListItem(
            id: 1,
            name: "Test",
            russian: nil,
            image: nil,
            url: nil,
            kind: "tv",
            score: "8.5",
            status: "ongoing",
            episodes: total,
            episodesAired: aired,
            airedOn: nil,
            releasedOn: nil
        )
    }
}
