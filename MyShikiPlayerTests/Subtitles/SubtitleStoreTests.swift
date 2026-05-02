//
//  SubtitleStoreTests.swift
//  MyShikiPlayerTests
//

import XCTest
@testable import MyShikiPlayer

@MainActor
final class SubtitleStoreTests: XCTestCase {

  private var service: StubAnime365Service!
  private var offsetStorage: SubtitleOffsetStorage!
  private var store: SubtitleStore!
  private var suiteName: String!

  override func setUp() {
    super.setUp()
    service = StubAnime365Service()
    suiteName = "test.subtitlestore.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    offsetStorage = SubtitleOffsetStorage(defaults: defaults)
    setupStore(vttBody: vttFixture)
  }

  override func tearDown() {
    MockURLProtocol.handler = nil
    UserDefaults.standard.removePersistentDomain(forName: suiteName)
    store = nil
    offsetStorage = nil
    service = nil
    suiteName = nil
    super.tearDown()
  }

  // MARK: - reset()

  func testResetWipesAllRuntimeState() {
    store.reset(shikimoriId: 1, episode: 1, translationId: nil)
    XCTAssertEqual(store.availableTracks, [])
    XCTAssertNil(store.selectedTrack)
    XCTAssertEqual(store.loadedCues, [])
    XCTAssertNil(store.loadedAssBytes)
    XCTAssertFalse(store.isLoadingTracks)
    XCTAssertFalse(store.isLoadingTrackContent)
    XCTAssertNil(store.errorMessage)
  }

  func testResetDoesNotCallService() {
    store.reset(shikimoriId: 1, episode: 1, translationId: nil)
    XCTAssertEqual(service.callCount, 0, "reset() must not trigger a network call")
  }

  func testResetRestoresPersistedOffset() {
    offsetStorage.setOffset(3.5, forShikimoriId: 10, translationId: 5)
    store.reset(shikimoriId: 10, episode: 1, translationId: 5)
    XCTAssertEqual(store.timeOffset, 3.5)
  }

  func testResetSetsContextCoordinates() {
    store.reset(shikimoriId: 7, episode: 3, translationId: 99)
    XCTAssertEqual(store.shikimoriId, 7)
    XCTAssertEqual(store.episode, 3)
    XCTAssertEqual(store.translationId, 99)
  }

  // MARK: - requestTracks()

  func testRequestTracksPopulatesAvailableTracks() async {
    service.result = .success(makeSearchResult(count: 2))
    store.reset(shikimoriId: 1, episode: 1, translationId: nil)
    await store.requestTracks()
    XCTAssertEqual(store.availableTracks.count, 2)
    XCTAssertNil(store.errorMessage)
  }

  func testRequestTracksIsIdempotentForSameEpisode() async {
    service.result = .success(makeSearchResult(count: 1))
    store.reset(shikimoriId: 1, episode: 1, translationId: nil)
    await store.requestTracks()
    await store.requestTracks()
    XCTAssertEqual(service.callCount, 1, "Second call for same episode must not hit service")
  }

  func testRequestTracksRefetchesAfterReset() async {
    service.result = .success(makeSearchResult(count: 1))
    store.reset(shikimoriId: 1, episode: 1, translationId: nil)
    await store.requestTracks()
    store.reset(shikimoriId: 1, episode: 2, translationId: nil)
    await store.requestTracks()
    XCTAssertEqual(service.callCount, 2)
  }

  func testRequestTracksOnErrorSetsErrorMessageAndEmptyTracks() async {
    service.result = .failure(Anime365Error.noSeriesForShikimoriId)
    store.reset(shikimoriId: 1, episode: 1, translationId: nil)
    await store.requestTracks()
    XCTAssertEqual(store.availableTracks, [])
    XCTAssertNotNil(store.errorMessage)
  }

  func testRequestTracksWithNilContextIsNoOp() async {
    store.reset(shikimoriId: nil, episode: nil, translationId: nil)
    await store.requestTracks()
    XCTAssertEqual(service.callCount, 0)
  }

  // MARK: - selectTrack()

  func testSelectNilClearsLoadedContent() async {
    await store.selectTrack(nil)
    XCTAssertNil(store.selectedTrack)
    XCTAssertEqual(store.loadedCues, [])
    XCTAssertNil(store.loadedAssBytes)
  }

  func testSelectTrackLoadsVTTCues() async {
    let track = makeTrack(id: 1, withAss: false)
    await store.selectTrack(track)
    XCTAssertEqual(store.selectedTrack?.id, 1)
    XCTAssertFalse(store.loadedCues.isEmpty)
  }

  func testSelectTrackLoadsAssWhenURLPresent() async {
    let track = makeTrack(id: 2, withAss: true)
    await store.selectTrack(track)
    // Both VTT and ASS loaders are served by the same MockURLProtocol handler
    // (which returns the VTT body — content doesn't matter for this test).
    XCTAssertNotNil(store.loadedAssBytes)
  }

  func testSelectSameTrackTwiceIsNoOp() async {
    let track = makeTrack(id: 3, withAss: false)
    await store.selectTrack(track)
    let cuesAfterFirst = store.loadedCues.count
    await store.selectTrack(track)
    XCTAssertEqual(store.loadedCues.count, cuesAfterFirst)
  }

  func testSelectTrackSetsSelectedTrack() async {
    let track = makeTrack(id: 5, withAss: false)
    await store.selectTrack(track)
    XCTAssertEqual(store.selectedTrack, track)
  }

  // MARK: - cue(atVideoTime:)

  func testCueLookupReturnsCueWithinRange() async {
    await loadCues(from: vttTwoCues)
    XCTAssertEqual(store.cue(atVideoTime: 10.5)?.text, "Alpha")
    XCTAssertEqual(store.cue(atVideoTime: 20.0)?.text, "Beta")
  }

  func testCueLookupReturnsNilInGap() async {
    await loadCues(from: vttTwoCues)
    XCTAssertNil(store.cue(atVideoTime: 15.0))
  }

  func testCueLookupReturnsNilBeforeFirstCue() async {
    await loadCues(from: vttTwoCues)
    XCTAssertNil(store.cue(atVideoTime: 5.0))
  }

  func testCueLookupReturnsNilAfterLastCue() async {
    await loadCues(from: vttTwoCues)
    XCTAssertNil(store.cue(atVideoTime: 30.0))
  }

  func testCueBoundaryStartIsInclusive() async {
    await loadCues(from: vttTwoCues)
    XCTAssertNotNil(store.cue(atVideoTime: 10.0))
  }

  func testCueBoundaryEndIsExclusive() async {
    await loadCues(from: vttTwoCues)
    XCTAssertNil(store.cue(atVideoTime: 12.0))
  }

  func testCueLookupWithPositiveOffset() async {
    // offset = +2 → adjusted = t - 2. Cue at [10, 12].
    // t=12.5 → adjusted=10.5 → inside. t=11.5 → adjusted=9.5 → before.
    await loadCues(from: vttTwoCues)
    store.setOffset(2.0)
    XCTAssertNil(store.cue(atVideoTime: 11.5), "adjusted=9.5, before cue start")
    XCTAssertNotNil(store.cue(atVideoTime: 12.5), "adjusted=10.5, inside cue")
  }

  func testCueLookupWithNegativeOffset() async {
    // offset = -3 → adjusted = t + 3. Cue at [10, 12].
    // t=8.0 → adjusted=11.0 → inside. t=5.0 → adjusted=8.0 → before.
    await loadCues(from: vttTwoCues)
    store.setOffset(-3.0)
    XCTAssertNotNil(store.cue(atVideoTime: 8.0), "adjusted=11.0, inside cue")
    XCTAssertNil(store.cue(atVideoTime: 5.0), "adjusted=8.0, before cue")
  }

  // MARK: - adjustedTime(forVideoTime:)

  func testAdjustedTimeSubtractsOffset() {
    store.setOffset(3.0)
    XCTAssertEqual(store.adjustedTime(forVideoTime: 10.0), 7.0)
  }

  func testAdjustedTimeWithZeroOffsetIsIdentity() {
    XCTAssertEqual(store.adjustedTime(forVideoTime: 42.5), 42.5)
  }

  // MARK: - Offset persistence

  func testSetOffsetPersistsThroughStorage() {
    store.reset(shikimoriId: 10, episode: 1, translationId: 5)
    store.setOffset(2.0)
    let stored = offsetStorage.offset(forShikimoriId: 10, translationId: 5)
    XCTAssertEqual(stored, 2.0)
  }

  func testAdjustOffsetAccumulates() {
    store.reset(shikimoriId: 1, episode: 1, translationId: 1)
    store.setOffset(1.0)
    store.adjustOffset(by: 0.5)
    XCTAssertEqual(store.timeOffset, 1.5)
  }

  func testResetOffsetClearsToZero() {
    store.reset(shikimoriId: 1, episode: 1, translationId: 1)
    store.setOffset(5.0)
    store.resetOffset()
    XCTAssertEqual(store.timeOffset, 0)
    XCTAssertEqual(offsetStorage.offset(forShikimoriId: 1, translationId: 1), 0)
  }

  // MARK: - Helpers

  private func setupStore(vttBody: String) {
    MockURLProtocol.handler = { _ in
      let response = HTTPURLResponse(
        url: URL(string: "https://example.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      return (response, Data(vttBody.utf8))
    }
    store = SubtitleStore(
      service: service,
      offsetStorage: offsetStorage,
      session: MockURLSession.make()
    )
  }

  private func loadCues(from vttBody: String) async {
    setupStore(vttBody: vttBody)
    let track = makeTrack(id: 99, withAss: false)
    await store.selectTrack(track)
  }

  private func makeTrack(id: Int, withAss: Bool) -> SubtitleTrack {
    SubtitleTrack(
      id: id,
      language: .ru,
      studioName: "Russian",
      fullTitle: nil,
      vttURL: URL(string: "https://example.com/\(id).vtt")!,
      assURL: withAss ? URL(string: "https://example.com/\(id).ass")! : nil
    )
  }
}

// MARK: - VTT fixtures

private let vttFixture = """
WEBVTT

1
00:00:01.000 --> 00:00:03.000
Line one.

2
00:00:04.000 --> 00:00:06.000
Line two.
"""

private let vttTwoCues = """
WEBVTT

1
00:00:10.000 --> 00:00:12.000
Alpha

2
00:00:20.000 --> 00:00:22.000
Beta
"""

// MARK: - Stub service

@MainActor
private final class StubAnime365Service: Anime365ServicingProtocol {
  var result: Result<SubtitleSearchResult, Error> = .success(makeSearchResult(count: 0))
  private(set) var callCount = 0

  func searchSubtitles(
    shikimoriId: Int,
    episode: Int,
    lang: Anime365LangFilter,
    checkAss: Bool
  ) async throws -> SubtitleSearchResult {
    callCount += 1
    return try result.get()
  }
}

// MARK: - Fixtures

private func makeSearchResult(count: Int) -> SubtitleSearchResult {
  let candidates = (0..<count).map { i in
    SubtitleCandidate(
      translationId: i + 1,
      type: "subRu",
      typeKind: "sub",
      title: "Track \(i + 1)",
      authorsSummary: "Studio \(i + 1)",
      assURL: URL(string: "https://cdn.example.com/\(i).ass")!,
      vttURL: URL(string: "https://cdn.example.com/\(i).vtt")!
    )
  }
  return SubtitleSearchResult(
    shikimoriId: 1,
    requestedEpisode: 1,
    seriesId: 1,
    seriaId: 1,
    title: "Test Anime",
    subtitles: candidates
  )
}
