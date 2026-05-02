//
//  SubtitlesAssembly.swift
//  MyShikiPlayer
//
//  Composition root for the subtitles feature. Wires all subtitle
//  dependencies together and vends the assembled store and settings
//  as a single value held by PlayerView.
//

import Foundation

@MainActor
struct SubtitlesAssembly {
  let store: SubtitleStore
  let settings: SubtitleSettings

  init() {
    let endpointStore = SubtitleEndpointStore.shared
    let service = Anime365Service(endpointStore: endpointStore)
    let offsetStorage = SubtitleOffsetStorage.shared
    self.settings = SubtitleSettings.shared
    self.store = SubtitleStore(service: service, offsetStorage: offsetStorage)
  }
}
