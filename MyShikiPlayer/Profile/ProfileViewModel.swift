//
//  ProfileViewModel.swift
//  MyShikiPlayer
//
//  Thin layer over ProfileRepo. Works with userId taken from auth.
//

import Foundation
import Combine

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var profile: UserProfile?
    @Published private(set) var favourites: [AnimeListItem] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private let repository: ProfileRepository

    init(repository: ProfileRepository = ProfileRepo.shared) {
        self.repository = repository
    }

    func reload(configuration: ShikimoriConfiguration, userId: Int, forceRefresh: Bool = false) async {
        if !forceRefresh, let cached = repository.cachedSnapshot(userId: userId, allowStale: true) {
            apply(cached)
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
            apply(snap)
        } catch {
            if profile == nil {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    private func apply(_ snap: ProfileRepo.Snapshot) {
        profile = snap.profile
        favourites = snap.favourites
    }

    // MARK: - Derived data

    /// Anime status distribution: non-empty buckets only.
    var statusBuckets: [UserStatBucket] {
        (profile?.stats?.statuses?.anime ?? []).filter { $0.count >= 1 }
    }

    /// Distribution of scores 1-10. Returns a 10-element array indexed by score:
    /// `result[0]` = count of "1", `result[9]` = count of "10". Empty buckets are 0.
    var ratingHistogram: [Int] {
        var bins = Array(repeating: 0, count: 10)
        for bucket in profile?.stats?.scores?.anime ?? [] {
            guard let name = bucket.name, let score = Int(name), (1...10).contains(score) else { continue }
            bins[score - 1] = bucket.count
        }
        return bins
    }

    /// Total number of scores used for averaging.
    var averageScore: Double? {
        let bins = ratingHistogram
        let total = bins.reduce(0, +)
        guard total > 0 else { return nil }
        var weighted = 0
        for (idx, count) in bins.enumerated() {
            weighted += (idx + 1) * count
        }
        return Double(weighted) / Double(total)
    }

    /// Total number of titles across all anime statuses.
    var totalTitles: Int {
        statusBuckets.reduce(0) { $0 + $1.count }
    }
}
