//
//  MyListIndexTests.swift
//  MyShikiPlayerTests
//

import XCTest
@testable import MyShikiPlayer

/// Covers how `MyListIndex` reacts to cache events — the part that decides
/// whether a title disappears from the "not in my list" grid right after the
/// user sets a status on it. A removal posts BOTH `.cacheUserRateRemoved` and
/// a payload-less `.cacheUserRateDidChange`, so the order of those two must
/// not put the id back.
@MainActor
final class MyListIndexTests: XCTestCase {

    func testSettingAStatusAddsTheTitle() async {
        let index = MyListIndex()

        CacheEvents.postUserRateChanged(
            animeId: 42,
            userId: 1,
            payload: CacheEvents.UserRatePayload(
                rateId: 7,
                status: "planned",
                score: 0,
                episodes: 0,
                updatedAt: nil
            )
        )

        await waitUntil { index.contains(42) }
        XCTAssertEqual(index.status(for: 42), .planned)
    }

    /// The poster stripe follows the status, so a change must overwrite it —
    /// not just mark the title as "somewhere in the list".
    func testChangingAStatusUpdatesIt() async {
        let index = MyListIndex()
        CacheEvents.postUserRateChanged(
            animeId: 42,
            userId: 1,
            payload: CacheEvents.UserRatePayload(
                rateId: 7, status: "watching", score: 0, episodes: 3, updatedAt: nil
            )
        )
        await waitUntil { index.status(for: 42) == .watching }

        CacheEvents.postUserRateChanged(
            animeId: 42,
            userId: 1,
            payload: CacheEvents.UserRatePayload(
                rateId: 7, status: "completed", score: 8, episodes: 12, updatedAt: nil
            )
        )

        await waitUntil { index.status(for: 42) == .completed }
        XCTAssertEqual(index.status(for: 42), .completed)
    }

    func testRemovingATitleTakesItOutDespiteTheImplicitChangeEvent() async {
        let index = MyListIndex()
        CacheEvents.postUserRateChanged(
            animeId: 42,
            userId: 1,
            payload: CacheEvents.UserRatePayload(
                rateId: 7, status: "planned", score: 0, episodes: 0, updatedAt: nil
            )
        )
        await waitUntil { index.contains(42) }

        CacheEvents.postUserRateRemoved(animeId: 42, userId: 1)

        await waitUntil { !index.contains(42) }
        XCTAssertFalse(index.contains(42))
    }

    func testClearAllEmptiesTheIndex() async {
        let index = MyListIndex()
        CacheEvents.postUserRateChanged(
            animeId: 42,
            userId: 1,
            payload: CacheEvents.UserRatePayload(
                rateId: 7, status: "watching", score: 0, episodes: 0, updatedAt: nil
            )
        )
        await waitUntil { index.contains(42) }

        CacheEvents.postClearAllCaches()

        await waitUntil { index.statuses.isEmpty }
        XCTAssertTrue(index.statuses.isEmpty)
        XCTAssertFalse(index.isReady)
    }

    /// Observers hop through `Task { @MainActor }`, so the effect lands on a
    /// later turn of the main actor — poll instead of asserting immediately.
    private func waitUntil(
        timeout: TimeInterval = 1.0,
        _ condition: () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
