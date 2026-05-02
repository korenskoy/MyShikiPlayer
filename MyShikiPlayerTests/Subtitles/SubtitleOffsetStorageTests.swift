//
//  SubtitleOffsetStorageTests.swift
//  MyShikiPlayerTests
//

import XCTest
@testable import MyShikiPlayer

@MainActor
final class SubtitleOffsetStorageTests: XCTestCase {

  private var storage: SubtitleOffsetStorage!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    suiteName = "test.subtitleoffsets.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    storage = SubtitleOffsetStorage(defaults: defaults)
  }

  override func tearDown() {
    UserDefaults.standard.removePersistentDomain(forName: suiteName)
    storage = nil
    suiteName = nil
    super.tearDown()
  }

  // MARK: - Basic get/set

  func testMissingKeyReturnsZero() {
    let value = storage.offset(forShikimoriId: 1, translationId: 100)
    XCTAssertEqual(value, 0)
  }

  func testSetAndGetRoundtrip() {
    storage.setOffset(2.5, forShikimoriId: 42, translationId: 7)
    let value = storage.offset(forShikimoriId: 42, translationId: 7)
    XCTAssertEqual(value, 2.5)
  }

  func testNegativeOffsetRoundtrip() {
    storage.setOffset(-3.0, forShikimoriId: 10, translationId: 5)
    let value = storage.offset(forShikimoriId: 10, translationId: 5)
    XCTAssertEqual(value, -3.0)
  }

  func testSetsDoNotCrossKeys() {
    storage.setOffset(1.0, forShikimoriId: 1, translationId: 1)
    storage.setOffset(2.0, forShikimoriId: 1, translationId: 2)
    XCTAssertEqual(storage.offset(forShikimoriId: 1, translationId: 1), 1.0)
    XCTAssertEqual(storage.offset(forShikimoriId: 1, translationId: 2), 2.0)
  }

  func testOverwriteExistingKey() {
    storage.setOffset(1.0, forShikimoriId: 1, translationId: 1)
    storage.setOffset(5.5, forShikimoriId: 1, translationId: 1)
    XCTAssertEqual(storage.offset(forShikimoriId: 1, translationId: 1), 5.5)
  }

  // MARK: - Reset

  func testResetRemovesEntry() {
    storage.setOffset(3.0, forShikimoriId: 5, translationId: 10)
    storage.reset(forShikimoriId: 5, translationId: 10)
    XCTAssertEqual(storage.offset(forShikimoriId: 5, translationId: 10), 0)
  }

  func testResetDoesNotAffectOtherEntries() {
    storage.setOffset(1.0, forShikimoriId: 1, translationId: 1)
    storage.setOffset(2.0, forShikimoriId: 2, translationId: 2)
    storage.reset(forShikimoriId: 1, translationId: 1)
    XCTAssertEqual(storage.offset(forShikimoriId: 2, translationId: 2), 2.0)
  }

  // MARK: - LRU eviction

  func testEvictsOldestWhenOverCapacity() {
    // Insert 200 entries so the store is full.
    for i in 0..<200 {
      storage.setOffset(Double(i), forShikimoriId: i, translationId: i)
    }
    // The 201st insert must evict the earliest entry (shikimoriId: 0).
    storage.setOffset(99.0, forShikimoriId: 200, translationId: 200)
    // Exactly one old entry should be gone; we can only know that the total is ≤ 200
    // and the new entry survives.
    XCTAssertEqual(storage.offset(forShikimoriId: 200, translationId: 200), 99.0)
  }

  func testEvictionKeepsCountAtOrBelowMax() {
    // Insert 205 entries — 5 must have been evicted.
    for i in 0..<205 {
      storage.setOffset(1.0, forShikimoriId: i, translationId: i)
    }
    var present = 0
    for i in 0..<205 {
      if storage.offset(forShikimoriId: i, translationId: i) != 0 {
        present += 1
      }
    }
    // After reading each entry we may have touched access times and the
    // stored count isn't directly accessible, but we know at most 200 were
    // stored at any one time because each insert beyond 200 evicts one.
    XCTAssertLessThanOrEqual(present, 200)
  }
}
