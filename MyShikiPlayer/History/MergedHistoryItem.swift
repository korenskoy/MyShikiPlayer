//
//  MergedHistoryItem.swift
//  MyShikiPlayer
//
//  Unified model for the History UI: one entry = one row in the list.
//  The source can be local (player's journal) or remote (Shikimori
//  /users/{id}/history). On collision, dedup keeps the local one.
//

import Foundation

struct MergedHistoryItem: Identifiable, Equatable {
    enum Source: Equatable {
        /// Local player event. `action` = the "most advanced" action from the
        /// collapsed group (started/progress/completed) — the rest are folded in.
        /// `eventIds` lists all original `WatchHistoryStore.Event.id`s that
        /// entered the collapse (needed for deletion).
        case local(action: WatchHistoryStore.Action, eventIds: [UUID])
        /// Remote Shikimori event. `rawDescription` is text already stripped
        /// of HTML ("Просмотрен 3-й эпизод", "Поставлена оценка 8").
        case remote(rawDescription: String)
    }

    let id: String
    let shikimoriId: Int
    /// Episode number. `nil` for remote rate/status/favourite — those
    /// have no link to a specific episode.
    let episode: Int?
    let title: String
    /// Poster URL, if it could be pulled from the remote target. Local
    /// events carry no poster — the UI fetches it via `PosterEnricher`.
    let posterURL: String?
    let occurredAt: Date
    let source: Source

    var isLocal: Bool {
        if case .local = source { return true }
        return false
    }

    /// `eventIds` of the local collapse — for `WatchHistoryStore.remove`.
    /// An empty array for remote items.
    var localEventIds: [UUID] {
        if case let .local(_, ids) = source { return ids }
        return []
    }
}
