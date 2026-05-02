//
//  SubtitleTrackPicker.swift
//  MyShikiPlayer
//
//  Grouped picker: tracks listed under their language section, with the
//  user's preferred language pinned to the top. Pure presenter.
//

import SwiftUI

struct SubtitleTrackPicker: View {
  let store: SubtitleStore
  /// Preferred language. Group with this language is rendered first; nil keeps the API order.
  let preferredLanguage: SubtitleLanguage?

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      offRow
      ForEach(orderedGroups, id: \.language) { group in
        languageGroup(group)
      }
    }
    .disabled(store.isLoadingTrackContent)
    .opacity(store.isLoadingTrackContent ? 0.5 : 1)
  }

  // MARK: - Off row

  private var offRow: some View {
    PlayerChoiceRow(
      title: "Выкл",
      subtitle: nil,
      isSelected: store.selectedTrack == nil,
      onSelect: { Task { await store.selectTrack(nil) } }
    )
  }

  // MARK: - Language group

  @ViewBuilder
  private func languageGroup(_ group: TrackGroup) -> some View {
    Text(group.language.groupTitle)
      .font(.dsLabel(10, weight: .bold))
      .tracking(1.5)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 10)
      .padding(.top, 8)
      .padding(.bottom, 2)

    ForEach(group.tracks) { track in
      trackRow(track)
    }
  }

  private func trackRow(_ track: SubtitleTrack) -> some View {
    PlayerChoiceRow(
      title: track.studioName,
      subtitle: nil,
      isSelected: track.id == store.selectedTrack?.id,
      onSelect: { Task { await store.selectTrack(track) } }
    )
    .help(track.fullTitle ?? track.studioName)
  }

  // MARK: - Grouping

  private struct TrackGroup {
    let language: SubtitleLanguage
    let tracks: [SubtitleTrack]
  }

  /// Groups tracks by `language` preserving API order within each group.
  /// The preferred-language group is moved to the top.
  private var orderedGroups: [TrackGroup] {
    var bucket: [SubtitleLanguage: [SubtitleTrack]] = [:]
    var insertionOrder: [SubtitleLanguage] = []

    for track in store.availableTracks {
      let key = track.language
      if bucket[key] == nil {
        bucket[key] = []
        insertionOrder.append(key)
      }
      bucket[key]?.append(track)
    }

    var orderedKeys = insertionOrder
    if let preferred = preferredLanguage,
       let index = orderedKeys.firstIndex(of: preferred) {
      let pinned = orderedKeys.remove(at: index)
      orderedKeys.insert(pinned, at: 0)
    }

    return orderedKeys.compactMap { key in
      guard let tracks = bucket[key], !tracks.isEmpty else { return nil }
      return TrackGroup(language: key, tracks: tracks)
    }
  }
}
