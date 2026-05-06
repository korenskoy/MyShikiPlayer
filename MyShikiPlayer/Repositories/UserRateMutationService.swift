//
//  UserRateMutationService.swift
//  MyShikiPlayer
//
//  Owner of every Shikimori user_rate / favorite mutation. Centralises the
//  three branches (create / update / delete) plus favorite toggle so VMs
//  hold no `ShikimoriRESTClient` of their own and only see typed results.
//
//  Cache invalidation events (`CacheEvents.*`) are posted from inside this
//  service — repos that subscribe to them (`AnimeDetailRepo`,
//  `HomeSectionsRepo`, `ProfileRepo`, `HistoryRepo`) drop affected entries
//  uniformly, no matter which screen issued the change.
//

import Foundation

/// Public-facing outcome of a successful user_rate mutation. Mirrors the
/// fields VMs need to reflect on screen — it's intentionally narrower than
/// `UserRateV2` so consumers don't depend on REST-decoder details.
struct UserRateMutationResult: Equatable, Sendable {
    let rateId: Int
    let status: String
    let score: Int?
    let episodesWatched: Int
}

/// Mutation surface for user_rate + favorites. VMs depend on the protocol
/// so tests can inject a fake without wiring up REST.
@MainActor
protocol UserRateMutating: AnyObject {
    /// PATCHes an existing `user_rate`. `nil` fields are omitted from the
    /// request body — the server preserves their previous values. To
    /// remove a rate entirely, call `deleteUserRate(...)` instead.
    func updateUserRate(
        configuration: ShikimoriConfiguration,
        animeId: Int,
        userId: Int,
        rateId: Int,
        status: String?,
        score: Int?,
        episodesWatched: Int?
    ) async throws -> UserRateMutationResult

    /// Creates a fresh `user_rate`. `status` is required by the API.
    func createUserRate(
        configuration: ShikimoriConfiguration,
        animeId: Int,
        userId: Int,
        status: String,
        score: Int?,
        episodesWatched: Int?
    ) async throws -> UserRateMutationResult

    /// Removes an existing `user_rate` and notifies subscribed caches.
    func deleteUserRate(
        configuration: ShikimoriConfiguration,
        animeId: Int,
        userId: Int,
        rateId: Int
    ) async throws

    /// Toggles favorite state. Returns the new state — VMs reflect it
    /// without needing a separate fetch.
    func toggleFavorite(
        configuration: ShikimoriConfiguration,
        animeId: Int,
        userId: Int,
        currentlyFavorite: Bool
    ) async throws -> Bool
}

@MainActor
final class UserRateMutationService: UserRateMutating {
    static let shared = UserRateMutationService()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - User rate

    func updateUserRate(
        configuration: ShikimoriConfiguration,
        animeId: Int,
        userId: Int,
        rateId: Int,
        status: String?,
        score: Int?,
        episodesWatched: Int?
    ) async throws -> UserRateMutationResult {
        let rest = ShikimoriRESTClient(configuration: configuration, session: session)
        let body = UserRateV2UpdateBody(userRate: .init(
            chapters: nil,
            episodes: episodesWatched.map(String.init),
            volumes: nil,
            rewatches: nil,
            score: score.map(String.init),
            status: status,
            text: nil
        ))
        let updated = try await rest.updateUserRate(id: rateId, body: body)
        let result = UserRateMutationResult(
            rateId: updated.id,
            status: updated.status,
            score: updated.score,
            episodesWatched: updated.episodes
        )
        postChanged(animeId: animeId, userId: userId, result: result)
        return result
    }

    func deleteUserRate(
        configuration: ShikimoriConfiguration,
        animeId: Int,
        userId: Int,
        rateId: Int
    ) async throws {
        let rest = ShikimoriRESTClient(configuration: configuration, session: session)
        try await rest.deleteUserRate(id: rateId)
        CacheEvents.postUserRateRemoved(animeId: animeId, userId: userId)
    }

    func createUserRate(
        configuration: ShikimoriConfiguration,
        animeId: Int,
        userId: Int,
        status: String,
        score: Int?,
        episodesWatched: Int?
    ) async throws -> UserRateMutationResult {
        let rest = ShikimoriRESTClient(configuration: configuration, session: session)
        let body = UserRateV2CreateBody(userRate: .init(
            userId: String(userId),
            targetId: String(animeId),
            targetType: "Anime",
            status: status,
            score: score.map(String.init),
            chapters: nil,
            episodes: episodesWatched.map(String.init),
            volumes: nil,
            rewatches: nil,
            text: nil
        ))
        let created = try await rest.createUserRate(body)
        let result = UserRateMutationResult(
            rateId: created.id,
            status: created.status,
            score: created.score,
            episodesWatched: created.episodes
        )
        postChanged(animeId: animeId, userId: userId, result: result)
        return result
    }

    // MARK: - Favorites

    func toggleFavorite(
        configuration: ShikimoriConfiguration,
        animeId: Int,
        userId: Int,
        currentlyFavorite: Bool
    ) async throws -> Bool {
        let rest = ShikimoriRESTClient(configuration: configuration, session: session)
        let desired = !currentlyFavorite
        if desired {
            try await rest.addFavorite(animeId: animeId)
        } else {
            try await rest.removeFavorite(animeId: animeId)
        }
        CacheEvents.postFavoriteToggled(animeId: animeId, userId: userId)
        return desired
    }

    // MARK: - Helpers

    private func postChanged(animeId: Int, userId: Int, result: UserRateMutationResult) {
        let payload = CacheEvents.UserRatePayload(
            rateId: result.rateId,
            status: result.status,
            score: result.score ?? 0,
            episodes: result.episodesWatched,
            updatedAt: nil
        )
        CacheEvents.postUserRateChanged(animeId: animeId, userId: userId, payload: payload)
    }
}
