//
//  SubtitleStore.swift
//  MyShikiPlayer
//

import Combine
import Foundation
import Observation

// MARK: - Service protocol

/// Minimal surface required by SubtitleStore. Allows test injection without subclassing.
@MainActor
protocol Anime365ServicingProtocol {
  func searchSubtitles(
    shikimoriId: Int,
    episode: Int,
    lang: Anime365LangFilter,
    checkAss: Bool
  ) async throws -> SubtitleSearchResult
}

extension Anime365Service: Anime365ServicingProtocol {}

// MARK: - Store

@MainActor
@Observable
final class SubtitleStore {

  // MARK: - Public state

  private(set) var availableTracks: [SubtitleTrack] = []
  private(set) var selectedTrack: SubtitleTrack? = nil
  private(set) var loadedCues: [SubtitleCue] = []
  private(set) var loadedAssBytes: Data? = nil
  private(set) var isLoadingTracks: Bool = false
  private(set) var isLoadingTrackContent: Bool = false
  private(set) var errorMessage: String? = nil
  private(set) var timeOffset: Double = 0

  private(set) var shikimoriId: Int? = nil
  private(set) var episode: Int? = nil
  private(set) var translationId: Int? = nil

  // MARK: - Private state

  private let service: any Anime365ServicingProtocol
  private let offsetStorage: SubtitleOffsetStorage
  private let vttLoader: VTTLoader
  private let assLoader: ASSLoader

  // Cursor for cue(atVideoTime:). Marked @ObservationIgnored so mutations
  // inside that method do not trigger view updates.
  @ObservationIgnored private var lastCueIndex: Int = 0

  // MARK: - Init

  init(
    service: any Anime365ServicingProtocol,
    offsetStorage: SubtitleOffsetStorage,
    session: URLSession = .shared
  ) {
    self.service = service
    self.offsetStorage = offsetStorage
    self.vttLoader = VTTLoader(session: session)
    self.assLoader = ASSLoader(session: session)
  }

  // MARK: - Episode / translation reset

  /// Wipes runtime state for the current episode. Never triggers a network request.
  func reset(shikimoriId: Int?, episode: Int?, translationId: Int?) {
    self.shikimoriId = shikimoriId
    self.episode = episode
    self.translationId = translationId

    availableTracks = []
    selectedTrack = nil
    loadedCues = []
    loadedAssBytes = nil
    isLoadingTracks = false
    isLoadingTrackContent = false
    errorMessage = nil
    lastCueIndex = 0

    if let sid = shikimoriId, let tid = translationId {
      timeOffset = offsetStorage.offset(forShikimoriId: sid, translationId: tid)
    } else {
      timeOffset = 0
    }
  }

  // MARK: - Track loading

  /// Fetches available subtitle tracks from Anime365. Idempotent: returns immediately
  /// when tracks are already loaded for the current context (reset(...) clears them).
  func requestTracks() async {
    guard let sid = shikimoriId, let ep = episode else { return }
    if !availableTracks.isEmpty { return }

    isLoadingTracks = true
    errorMessage = nil

    defer { isLoadingTracks = false }

    do {
      let result = try await service.searchSubtitles(
        shikimoriId: sid,
        episode: ep,
        lang: .all,
        checkAss: false
      )
      availableTracks = result.subtitles.map { SubtitleTrack.make(from: $0) }
    } catch {
      availableTracks = []
      errorMessage = error.localizedDescription
    }
  }

  // MARK: - Track selection

  /// Selects a track and loads its content. Passing nil clears all loaded content.
  func selectTrack(_ track: SubtitleTrack?) async {
    guard track != selectedTrack else { return }

    selectedTrack = track
    loadedCues = []
    loadedAssBytes = nil
    errorMessage = nil
    lastCueIndex = 0

    guard let track else { return }

    isLoadingTrackContent = true
    defer { isLoadingTrackContent = false }

    // VTT and ASS are independent — fetch in parallel.
    async let cuesResult: [SubtitleCue]? = (try? await vttLoader.load(track.vttURL))
    async let assResult: Data? = {
      guard let url = track.assURL else { return nil }
      return try? await assLoader.loadRawBytes(url)
    }()

    let (cues, ass) = await (cuesResult, assResult)

    if let cues {
      // Sort by startTime: VTT spec allows out-of-order cues in theory.
      loadedCues = cues.sorted { $0.startTime < $1.startTime }
    } else {
      loadedCues = []
      errorMessage = "Не удалось загрузить субтитры."
    }
    loadedAssBytes = ass
  }

  // MARK: - Cue lookup (pure)

  /// Returns the cue active at the given video time, applying timeOffset.
  /// Mutates lastCueIndex (ObservationIgnored) but is otherwise pure from
  /// the caller's perspective — no Observable state changes.
  func cue(atVideoTime t: Double) -> SubtitleCue? {
    let adjusted = t - timeOffset
    let cues = loadedCues
    guard !cues.isEmpty else { return nil }

    // Clamp cursor to the current array bounds (track reload shrinks the array).
    if lastCueIndex >= cues.count { lastCueIndex = 0 }

    // Try the current cursor position first (O(1) steady state).
    if lastCueIndex < cues.count,
       adjusted >= cues[lastCueIndex].startTime,
       adjusted < cues[lastCueIndex].endTime {
      return cues[lastCueIndex]
    }

    // Walk forward from cursor for typical playback.
    var i = lastCueIndex
    while i < cues.count {
      let cue = cues[i]
      if adjusted < cue.startTime { break }
      if adjusted < cue.endTime {
        lastCueIndex = i
        return cue
      }
      i += 1
    }

    // Cursor is ahead of the adjusted time (seek backward) — binary search.
    var lo = 0
    var hi = cues.count - 1
    while lo <= hi {
      let mid = (lo + hi) / 2
      let cue = cues[mid]
      if adjusted < cue.startTime {
        hi = mid - 1
      } else if adjusted >= cue.endTime {
        lo = mid + 1
      } else {
        lastCueIndex = mid
        return cue
      }
    }

    // Between cues — park cursor near the next upcoming cue.
    lastCueIndex = min(lo, cues.count - 1)
    return nil
  }

  /// Returns the libass-adjusted time for a given video time.
  /// Pure derivation — no side effects.
  func adjustedTime(forVideoTime t: Double) -> Double {
    t - timeOffset
  }

  // MARK: - Offset management

  func setOffset(_ value: Double) {
    timeOffset = value
    persistOffset(value)
  }

  func adjustOffset(by delta: Double) {
    let newValue = timeOffset + delta
    timeOffset = newValue
    persistOffset(newValue)
  }

  func resetOffset() {
    timeOffset = 0
    guard let sid = shikimoriId, let tid = translationId else { return }
    offsetStorage.reset(forShikimoriId: sid, translationId: tid)
  }

  // MARK: - Session binding

  /// Subscribes to context changes on `session` and calls `reset(...)` on each
  /// change. The returned cancellable must be held by the caller; releasing it
  /// stops the subscription.
  func attach(to session: PlaybackSession) -> AnyCancellable {
    Publishers.CombineLatest3(
      session.$currentShikimoriId,
      session.$currentEpisode,
      session.$preferredTranslationId
    )
    .sink { [weak self] sid, ep, tid in
      self?.reset(shikimoriId: sid, episode: ep, translationId: tid)
    }
  }

  // MARK: - Private

  private func persistOffset(_ value: Double) {
    guard let sid = shikimoriId, let tid = translationId else { return }
    offsetStorage.setOffset(value, forShikimoriId: sid, translationId: tid)
  }
}
