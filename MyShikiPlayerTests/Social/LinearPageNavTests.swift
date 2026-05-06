//
//  LinearPageNavTests.swift
//  MyShikiPlayerTests
//
//  Pure-function tests for `LinearPageNav.pageItems(currentPage:totalPages:)`
//  — the page-window algorithm that picks which page chips and ellipses are
//  rendered in the topic comments pager.
//

import XCTest
@testable import MyShikiPlayer

final class LinearPageNavTests: XCTestCase {

    // MARK: - Helpers

    private typealias Item = LinearPageNav.PageItem

    private func items(_ current: Int, _ total: Int) -> [Item] {
        LinearPageNav.pageItems(currentPage: current, totalPages: total)
    }

    // MARK: - Empty / single-page edge cases

    func test_emptyForZeroOrOnePage() {
        XCTAssertEqual(items(1, 0), [])
        XCTAssertEqual(items(1, 1), [])
    }

    // MARK: - Short threads enumerate every page

    func test_shortThread_listsEveryPage_atOrUnderSeven() {
        XCTAssertEqual(items(1, 2), [.number(1), .number(2)])
        XCTAssertEqual(items(3, 5), (1...5).map { .number($0) })
        XCTAssertEqual(items(4, 7), (1...7).map { .number($0) })
    }

    // MARK: - Window expands to absorb a single-page gap

    func test_window_replacesSingletonGapWithExplicitNumber_left() {
        // total=18, cur=4 → left side would be [1, …, 3, …] but the gap is
        // a single page, so we expect `2` filled in instead of an ellipsis.
        XCTAssertEqual(
            items(4, 18),
            [.number(1), .number(2), .number(3), .number(4), .number(5), .ellipsis, .number(18)]
        )
    }

    func test_window_replacesSingletonGapWithExplicitNumber_right() {
        // total=18, cur=15 → right side singleton gap; expect `17` instead of `…`.
        XCTAssertEqual(
            items(15, 18),
            [.number(1), .ellipsis, .number(14), .number(15), .number(16), .number(17), .number(18)]
        )
    }

    // MARK: - Window keeps current chip surrounded by neighbours

    func test_window_middlePage_hasEllipsesBothSides() {
        // The screenshot case: total=18, cur=13.
        XCTAssertEqual(
            items(13, 18),
            [.number(1), .ellipsis, .number(12), .number(13), .number(14), .ellipsis, .number(18)]
        )
    }

    // MARK: - Window edges (current at 1 / 2 / total-1 / total)

    func test_window_currentAtFirstPage() {
        XCTAssertEqual(
            items(1, 18),
            [.number(1), .number(2), .ellipsis, .number(18)]
        )
    }

    func test_window_currentAtSecondPage() {
        XCTAssertEqual(
            items(2, 18),
            [.number(1), .number(2), .number(3), .ellipsis, .number(18)]
        )
    }

    func test_window_currentAtPenultimatePage() {
        XCTAssertEqual(
            items(17, 18),
            [.number(1), .ellipsis, .number(16), .number(17), .number(18)]
        )
    }

    func test_window_currentAtLastPage() {
        XCTAssertEqual(
            items(18, 18),
            [.number(1), .ellipsis, .number(17), .number(18)]
        )
    }

    // MARK: - Out-of-range current page clamps without crashing

    func test_currentPageBelowOne_clampsToFirst() {
        XCTAssertEqual(items(0, 18), items(1, 18))
        XCTAssertEqual(items(-5, 18), items(1, 18))
    }

    func test_currentPageAboveTotal_clampsToLast() {
        XCTAssertEqual(items(99, 18), items(18, 18))
    }

    // MARK: - Boundary at totalPages == 8 (first windowed size)

    func test_window_atFirstWindowedTotal_eight() {
        // cur=4 fills the singleton gap on the left; right has the standard ellipsis.
        XCTAssertEqual(
            items(4, 8),
            [.number(1), .number(2), .number(3), .number(4), .number(5), .ellipsis, .number(8)]
        )
        // cur=5 has a left ellipsis; right side singleton gap fills `7`.
        XCTAssertEqual(
            items(5, 8),
            [.number(1), .ellipsis, .number(4), .number(5), .number(6), .number(7), .number(8)]
        )
    }
}
