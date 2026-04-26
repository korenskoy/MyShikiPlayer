//
//  StreamSelector.swift
//  MyShikiPlayer
//
//  Pure helpers for picking a `MediaSource` out of a resolved set:
//  matching a studio at a quality hint, deriving a studio catalog from
//  already-resolved streams. No I/O — easy to unit-test in isolation.
//
//  Extracted from PlaybackSession.swift in Phase 4 to keep that facade thin.
//

import Foundation

enum StreamSelector {
    /// Pick the MediaSource matching `studioId`. When `qualityHint` is provided
    /// and a stream of the same quality exists for the target studio, use it —
    /// flipping between dubs at 720p must not silently downgrade to 360p.
    static func pickSource(
        in sources: [PlaybackSession.MediaSource],
        forStudioId studioId: Int,
        qualityHint: String?
    ) -> PlaybackSession.MediaSource? {
        let candidates = sources.filter { $0.studioId == studioId }
        if let qualityHint,
           let exact = candidates.first(where: { $0.qualityLabel == qualityHint }) {
            return exact
        }
        return candidates.first
    }

    /// Derive a studio list from already-resolved sources — used as a fallback
    /// when the adapter does not expose `studios` separately.
    static func studios(from sources: [PlaybackSession.MediaSource]) -> [StudioOption] {
        var seen = Set<Int>()
        var result: [StudioOption] = []
        for source in sources {
            guard let id = source.studioId, seen.insert(id).inserted else { continue }
            let label = source.studioLabel?.trimmingCharacters(in: .whitespaces) ?? ""
            result.append(
                StudioOption(
                    provider: source.provider,
                    studioId: id,
                    studioLabel: label.isEmpty ? source.provider.rawValue.capitalized : label
                )
            )
        }
        return result
    }
}
