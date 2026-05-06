//
//  HomeViewModel.swift
//  MyShikiPlayer
//
//  Thin layer over HomeSectionsRepo: pulls a snapshot from cache or kicks off
//  a fresh request. Does not hold any network logic.
//

import Foundation
import Combine

struct HomeContinueItem: Identifiable, Codable, Sendable {
    let id: Int
    let anime: AnimeListItem
    let episodesWatched: Int
    /// Episodes already aired (for ongoings — the real upper bound).
    let episodesAired: Int?
    /// Total planned episodes (for completed shows usually equals episodesAired).
    let totalEpisodes: Int?
    let note: String

    /// Number of episodes used as the progress denominator:
    /// already aired for ongoings, total for completed shows.
    var effectiveDenominator: Int? {
        if let aired = episodesAired, aired > 0 { return aired }
        if let total = totalEpisodes, total > 0 { return total }
        return nil
    }

    var progress: Double {
        guard let total = effectiveDenominator, total > 0 else { return 0 }
        return min(1, Double(episodesWatched) / Double(total))
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var featuredHero: AnimeListItem?
    @Published private(set) var trending: [AnimeListItem] = []
    @Published private(set) var newEpisodes: [AnimeListItem] = []
    @Published private(set) var recommendations: [AnimeListItem] = []
    @Published private(set) var continueWatching: [HomeContinueItem] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private let repository: HomeRepository

    init(repository: HomeRepository = HomeSectionsRepo.shared) {
        self.repository = repository
    }

    func reload(configuration: ShikimoriConfiguration, userId: Int?, forceRefresh: Bool = false) async {
        // SWR: show any cached data (even stale) without a spinner.
        // A fresh snapshot is fetched in the background and replaces it.
        if !forceRefresh, let cached = repository.cachedSnapshot(userId: userId, allowStale: true) {
            apply(snapshot: cached)
        } else {
            isLoading = true
        }
        errorMessage = nil

        do {
            let snap = try await repository.snapshot(
                configuration: configuration,
                userId: userId,
                forceRefresh: forceRefresh
            )
            apply(snapshot: snap)
        } catch {
            if trending.isEmpty && continueWatching.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func apply(snapshot: HomeSectionsRepo.Snapshot) {
        trending = snapshot.trending
        newEpisodes = snapshot.newEpisodes
        recommendations = snapshot.recommendations
        continueWatching = snapshot.continueWatching
        featuredHero = snapshot.featuredHero
    }
}
