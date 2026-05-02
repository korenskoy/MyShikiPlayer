//
//  SubtitleCue.swift
//  MyShikiPlayer
//

import Foundation

struct SubtitleCue: Sendable, Hashable, Identifiable {
  let id: Int
  let startTime: Double
  let endTime: Double
  let text: String
}
