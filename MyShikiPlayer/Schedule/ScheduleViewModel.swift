//
//  ScheduleViewModel.swift
//  MyShikiPlayer
//
//  Thin layer over CalendarRepo: reads from cache or fetches. Groups
//  entries by calendar day (ru_RU locale, device time zone).
//

import Foundation
import Combine

struct ScheduleDaySection: Identifiable {
    /// Start of the local day — used as id and for headers.
    let day: Date
    let entries: [CalendarEntry]
    var id: Date { day }
}

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published private(set) var sections: [ScheduleDaySection] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    /// How many days ahead we show (including today).
    private let horizonDays: Int = 7

    func reload(configuration: ShikimoriConfiguration, forceRefresh: Bool = false) async {
        if !forceRefresh, let cached = CalendarRepo.shared.cached(allowStale: true) {
            sections = Self.group(entries: cached, horizon: horizonDays)
        } else {
            isLoading = true
        }
        errorMessage = nil
        do {
            let entries = try await CalendarRepo.shared.entries(
                configuration: configuration,
                forceRefresh: forceRefresh
            )
            sections = Self.group(entries: entries, horizon: horizonDays)
            // Posters for calendar titles in REST are often missing_ —
            // ask GraphQL to fetch the real ones.
            let missingIds = entries.filter { $0.anime.needsPosterEnrichment }.map(\.anime.id)
            if !missingIds.isEmpty {
                await PosterEnricher.shared.enrich(configuration: configuration, ids: missingIds)
                let enrichedEntries = entries.map { entry -> CalendarEntry in
                    guard entry.anime.needsPosterEnrichment,
                          let url = PosterEnricher.shared.cachedURL(id: entry.anime.id) else {
                        return entry
                    }
                    return CalendarEntry(
                        nextEpisodeAt: entry.nextEpisodeAt,
                        duration: entry.duration,
                        anime: entry.anime.withPoster(url: url)
                    )
                }
                sections = Self.group(entries: enrichedEntries, horizon: horizonDays)
            }
        } catch {
            if sections.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private static func group(entries: [CalendarEntry], horizon: Int) -> [ScheduleDaySection] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let horizonEnd = calendar.date(byAdding: .day, value: horizon, to: today) else { return [] }

        let filtered = entries.filter { entry in
            entry.nextEpisodeAt >= today && entry.nextEpisodeAt < horizonEnd
        }
        let grouped = Dictionary(grouping: filtered) { entry in
            calendar.startOfDay(for: entry.nextEpisodeAt)
        }
        let sortedKeys = grouped.keys.sorted()
        return sortedKeys.map { day in
            let sorted = (grouped[day] ?? []).sorted { $0.nextEpisodeAt < $1.nextEpisodeAt }
            return ScheduleDaySection(day: day, entries: sorted)
        }
    }
}
