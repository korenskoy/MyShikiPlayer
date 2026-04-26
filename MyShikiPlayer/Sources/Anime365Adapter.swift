//
//  Anime365Adapter.swift
//  MyShikiPlayer
//

import Foundation

struct Anime365Adapter: SourceAdapter {
    let provider: SourceProvider = .anime365

    func resolve(request: SourceResolutionRequest) async throws -> SourceResolutionResult {
        throw PlayerError.sourceUnavailable(provider.rawValue)
    }
}
