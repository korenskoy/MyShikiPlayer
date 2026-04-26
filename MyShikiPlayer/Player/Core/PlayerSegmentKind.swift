//
//  PlayerSegmentKind.swift
//  MyShikiPlayer
//
//  Shared classification of a playable segment inside an episode. Lives in
//  Core because both the playback session (auto-skip bookkeeping) and the
//  UI overlay (chapter rendering) need the same vocabulary, and we don't
//  want two parallel enums to drift apart.
//

import Foundation

enum PlayerSegmentKind: String, Hashable {
    case opening
    case partA
    case ending
    case partB
    case preview
}
