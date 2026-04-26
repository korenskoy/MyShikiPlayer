//
//  AnilibAdapter.swift
//  MyShikiPlayer
//

import Foundation

struct AnilibAdapter: SourceAdapter {
    let provider: SourceProvider = .anilib

    func resolve(request: SourceResolutionRequest) async throws -> SourceResolutionResult {
        throw PlayerError.sourceUnavailable(provider.rawValue)
    }
}
