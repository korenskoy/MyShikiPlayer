//
//  AnilibriaAdapter.swift
//  MyShikiPlayer
//

import Foundation

struct AnilibriaAdapter: SourceAdapter {
    let provider: SourceProvider = .anilibria

    func resolve(request: SourceResolutionRequest) async throws -> SourceResolutionResult {
        throw PlayerError.sourceUnavailable(provider.rawValue)
    }
}
