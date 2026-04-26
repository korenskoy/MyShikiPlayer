//
//  HistoryMerger.swift
//  MyShikiPlayer
//
//  Pure function: (local journal, remote page) → sorted list of
//  `MergedHistoryItem`. No network calls and no UI.
//
//  Algorithm:
//  1. Local events are collapsed by (shikimoriId, episode, calendar day):
//     each group keeps a single entry with the "most advanced" action
//     (completed > started > progress). This removes noise from the
//     30-second `progress` ticks and from started+completed pairs of the
//     same episode.
//  2. Remote entries are mapped into `MergedHistoryItem`. The episode
//     number is parsed from the description text (when possible).
//  3. Dedup IN FAVOR OF LOCAL: if remote has an episode and a local entry
//     with the same (shikimoriId, episode) exists within a ±10 min window,
//     the remote entry is dropped. Remote entries without an episode
//     (rate/status/favourite) are always kept — the local journal has no
//     such events.
//  4. The result is sorted by occurredAt desc.
//

import Foundation

enum HistoryMerger {
    /// Time window for matching local↔remote entries. ±10 minutes is a
    /// compromise between "we managed to sync to the server" and
    /// "random collision between different viewings".
    static let dedupeWindow: TimeInterval = 10 * 60

    static func merge(
        local: [WatchHistoryStore.Event],
        remote: [UserHistoryEntry],
        calendar: Calendar = .current
    ) -> [MergedHistoryItem] {
        let collapsedLocal = collapseLocal(local, calendar: calendar)
        let mappedRemote = remote.compactMap(mapRemote)
        let filteredRemote = mappedRemote.filter { rem in
            !collapsedLocal.contains { loc in
                guard let remEp = rem.episode, let locEp = loc.episode else { return false }
                guard loc.shikimoriId == rem.shikimoriId, locEp == remEp else { return false }
                return abs(loc.occurredAt.timeIntervalSince(rem.occurredAt)) <= dedupeWindow
            }
        }
        return (collapsedLocal + filteredRemote).sorted { $0.occurredAt > $1.occurredAt }
    }

    // MARK: - Local collapse

    private struct LocalKey: Hashable {
        let shikimoriId: Int
        let episode: Int
        let dayKey: String
    }

    static func collapseLocal(
        _ events: [WatchHistoryStore.Event],
        calendar: Calendar = .current
    ) -> [MergedHistoryItem] {
        var buckets: [LocalKey: [WatchHistoryStore.Event]] = [:]
        for event in events {
            let comps = calendar.dateComponents([.year, .month, .day], from: event.occurredAt)
            let dayKey = "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
            let key = LocalKey(shikimoriId: event.shikimoriId, episode: event.episode, dayKey: dayKey)
            buckets[key, default: []].append(event)
        }
        return buckets.map { key, group in
            let mostAdvanced = mostAdvancedAction(group.map(\.action))
            let latest = group.map(\.occurredAt).max() ?? Date.distantPast
            // Take the title from the freshest entry of the group — the user
            // could (in theory) rename the title, so we use the most recent.
            let representative = group.max(by: { $0.occurredAt < $1.occurredAt }) ?? group[0]
            return MergedHistoryItem(
                id: "local/\(key.shikimoriId)/\(key.episode)/\(key.dayKey)",
                shikimoriId: key.shikimoriId,
                episode: key.episode,
                title: representative.title,
                posterURL: nil,
                occurredAt: latest,
                source: .local(action: mostAdvanced, eventIds: group.map(\.id))
            )
        }
    }

    static func mostAdvancedAction(_ actions: [WatchHistoryStore.Action]) -> WatchHistoryStore.Action {
        if actions.contains(.completed) { return .completed }
        if actions.contains(.started) { return .started }
        return .progress
    }

    // MARK: - Remote mapping

    static func mapRemote(_ entry: UserHistoryEntry) -> MergedHistoryItem? {
        guard let target = entry.target, let createdAt = entry.createdAt else { return nil }
        let plain = ShikimoriText.toPlain(entry.description ?? "")
        let title: String = {
            if let r = target.russian, !r.isEmpty { return r }
            if let n = target.name, !n.isEmpty { return n }
            return "—"
        }()
        let posterRaw = target.image?.preview ?? target.image?.original
        let posterURL: String? = {
            guard let raw = posterRaw, !raw.isEmpty, !raw.contains("missing_") else { return nil }
            if raw.hasPrefix("http") { return raw }
            if raw.hasPrefix("/") { return ShikimoriURL.media(path: raw)?.absoluteString ?? raw }
            return raw
        }()
        let episode = extractEpisode(from: plain)
        return MergedHistoryItem(
            id: "remote/\(entry.id)",
            shikimoriId: target.id,
            episode: episode,
            title: title,
            posterURL: posterURL,
            occurredAt: createdAt,
            source: .remote(rawDescription: plain)
        )
    }

    /// Extracts an episode number from texts like "Просмотрен 3-й эпизод",
    /// "Просмотрено 12 эпизодов", "Эпизод 5" and similar. Returns nil for
    /// status/rate/favourite events — those have no episode number.
    static func extractEpisode(from text: String) -> Int? {
        let patterns: [String] = [
            #"(\d+)\s*[\-–]?\s*[ийея]*\s*эпизод"#,
            #"эпизод\w*\s*(\d+)"#,
            #"(\d+)\s*сери[ияй]"#,
            #"сери[ияйю]\w*\s*(\d+)"#,
        ]
        for pat in patterns {
            guard let regex = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, range: range),
               match.numberOfRanges > 1,
               let captured = Range(match.range(at: 1), in: text),
               let n = Int(text[captured]) {
                return n
            }
        }
        return nil
    }
}
