//
//  SubtitlesEnvironment.swift
//  MyShikiPlayer
//

import SwiftUI

private struct SubtitlesAssemblyKey: EnvironmentKey {
  static let defaultValue: SubtitlesAssembly? = nil
}

extension EnvironmentValues {
  var subtitlesAssembly: SubtitlesAssembly? {
    get { self[SubtitlesAssemblyKey.self] }
    set { self[SubtitlesAssemblyKey.self] = newValue }
  }
}
