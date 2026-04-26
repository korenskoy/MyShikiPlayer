//
//  AnilibertyAdapter.swift
//  MyShikiPlayer
//

import Foundation

struct AnilibertyAdapter: SourceAdapter {
    let provider: SourceProvider = .aniliberty

    func resolve(request: SourceResolutionRequest) async throws -> SourceResolutionResult {
        throw PlayerError.sourceUnavailable(provider.rawValue)
    }
}
