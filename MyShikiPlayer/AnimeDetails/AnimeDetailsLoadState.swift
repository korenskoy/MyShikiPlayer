//
//  AnimeDetailsLoadState.swift
//  MyShikiPlayer
//

import Foundation

enum AnimeDetailsLoadState: Equatable {
    case idle
    case loading
    case content
    case error(String)
}
