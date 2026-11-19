//
//  RequestThrottlerTests.swift
//  MyShikiPlayerTests
//

import XCTest
@testable import MyShikiPlayer

/// Covers `RequestThrottler` under concurrency — the case that produced 429s:
/// callers arriving while an earlier one slept all computed the same wake-up
/// time and left the gate together. Only lower bounds are asserted, so a slow
/// machine can't fail these.
final class RequestThrottlerTests: XCTestCase {

    func testConcurrentCallersAreSpacedByTheMinimumInterval() async {
        let throttler = RequestThrottler(minInterval: 0.1, windowDuration: 60, maxRequestsInWindow: .max)
        let start = Date()

        let exits = await withTaskGroup(of: TimeInterval.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    await throttler.waitTurn()
                    return Date().timeIntervalSince(start)
                }
            }
            var result: [TimeInterval] = []
            for await exit in group { result.append(exit) }
            return result.sorted()
        }

        // Four grants 0.1s apart: the last one leaves no earlier than 0.3s.
        XCTAssertGreaterThanOrEqual(exits[3], 0.27, "exits: \(exits)")
        for (earlier, later) in zip(exits, exits.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, 0.08, "exits: \(exits)")
        }
    }

    func testFullWindowWaitsForTheOldestGrantToExpire() async {
        let throttler = RequestThrottler(minInterval: 0, windowDuration: 0.3, maxRequestsInWindow: 2)
        let start = Date()

        await throttler.waitTurn()
        await throttler.waitTurn()
        await throttler.waitTurn()

        // The third call has to wait for the first grant to leave the window.
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(start), 0.27)
    }
}
