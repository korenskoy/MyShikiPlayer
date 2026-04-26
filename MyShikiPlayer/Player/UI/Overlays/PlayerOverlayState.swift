//
//  PlayerOverlayState.swift
//  MyShikiPlayer
//
//  Derived state for the new player overlay: visibility (with auto-hide),
//  chapters, time formatters. Does not own the source of truth —
//  everything is read from PlayerEngine/PlaybackSession.
//

import Foundation
import SwiftUI

struct PlayerChapter: Identifiable, Hashable {
    enum Kind { case opening, partA, ending, partB, preview }
    let id: String
    let label: String
    let start: Double
    let end: Double
    let kind: Kind

    var length: Double { max(0, end - start) }
}

enum PlayerChapterFactory {
    /// Builds up to two chapters from the source's skip ranges (opening + ending).
    /// Each chapter is included only when the corresponding range is known and
    /// inside the playable duration window. The scrub bar copes with any subset
    /// (none / opening only / ending only / both).
    static func chapters(
        duration: Double,
        opening: ClosedRange<Double>?,
        ending: ClosedRange<Double>?
    ) -> [PlayerChapter] {
        guard duration > 0 else { return [] }
        var out: [PlayerChapter] = []
        if let opening {
            out.append(
                PlayerChapter(
                    id: "op",
                    label: "ОП",
                    start: opening.lowerBound,
                    end: min(opening.upperBound, duration),
                    kind: .opening
                )
            )
        }
        if let ending {
            out.append(
                PlayerChapter(
                    id: "ed",
                    label: "ЭД",
                    start: ending.lowerBound,
                    end: min(ending.upperBound, duration),
                    kind: .ending
                )
            )
        }
        return out
    }
}

enum PlayerTimeFormatter {
    static func mmss(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}
