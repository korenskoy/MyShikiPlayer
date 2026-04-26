//
//  CalendarEntry.swift
//  MyShikiPlayer
//
//  A single entry from /api/calendar: time of the upcoming episode + anons.
//  The API does not return the episode number — we derive it as episodesAired + 1.
//

import Foundation

struct CalendarEntry: Codable, Sendable, Equatable {
    let nextEpisodeAt: Date
    let duration: Int?
    let anime: AnimeListItem

    /// Estimated number of the next episode. For an ongoing,
    /// `episodesAired` is the count of already aired episodes; the next one is +1.
    var estimatedEpisodeNumber: Int? {
        guard let aired = anime.episodesAired else { return nil }
        return aired + 1
    }
}
