//
//  MyListIndex.swift
//  MyShikiPlayer
//
//  The signed-in user's list as `animeId → status`, shared app-wide. Catalog
//  and calendar endpoints return nothing about the user, so this is where the
//  cards learn a title's list status, and where the "not in my list" filter
//  learns what to hide (Shikimori's `mylist` param cannot express absence).
//

import Combine
import Foundation

@MainActor
final class MyListIndex: ObservableObject {
    static let shared = MyListIndex()

    /// Meaningful only once `isReady` is set — before that it is simply empty.
    @Published private(set) var statuses: [Int: MyListStatus] = [:]
    /// Stays true across refreshes: once the list is known, a later reload
    /// must not switch the filter off and flash hidden titles back in.
    @Published private(set) var isReady: Bool = false

    private var loadedUserId: Int?
    private var loadTask: Task<Void, Never>?
    private let cacheObservers = CacheObserverBag()

    /// Internal rather than private so tests can use an isolated instance.
    init() {
        // A status change lands right away — cards and the filter must not
        // wait for a refetch. The implicit `.didChange` that follows a removal
        // carries no payload, so it is ignored here and the removal observer
        // below handles it.
        cacheObservers.add(CacheEvents.observeUserRateChanged { [weak self] animeId, _, payload in
            guard let raw = payload?.status, let status = MyListStatus(rawValue: raw) else { return }
            self?.statuses[animeId] = status
        })
        cacheObservers.add(CacheEvents.observeUserRateRemoved { [weak self] animeId, _ in
            self?.statuses[animeId] = nil
        })
        cacheObservers.add(CacheEvents.observeClearAll { [weak self] in
            self?.reset()
        })
    }

    func status(for animeId: Int) -> MyListStatus? {
        statuses[animeId]
    }

    func contains(_ animeId: Int) -> Bool {
        statuses[animeId] != nil
    }

    func loadIfNeeded(configuration: ShikimoriConfiguration, userId: Int) {
        guard !isReady || loadedUserId != userId else { return }
        guard loadTask == nil else { return }
        if let loadedUserId, loadedUserId != userId {
            // Another account's statuses must never bleed into this one.
            reset()
        }
        loadTask = Task { [weak self] in
            await self?.load(configuration: configuration, userId: userId)
        }
    }

    /// `/api/v2/user_rates` answers with the whole list in one response — it
    /// ignores `limit` and `page` — so there is nothing to paginate here.
    private func load(configuration: ShikimoriConfiguration, userId: Int) async {
        defer { loadTask = nil }
        var query = UserRatesListQuery()
        query.userId = userId
        query.targetType = "Anime"

        do {
            let rates = try await ShikimoriRESTClient(configuration: configuration).userRates(query: query)
            let loaded = Dictionary(
                rates.compactMap { rate in MyListStatus(rawValue: rate.status).map { (rate.targetId, $0) } },
                uniquingKeysWith: { _, latest in latest }
            )
            // A status set while the request was in flight is newer than what
            // the response carries — keep it.
            statuses = loaded.merging(statuses) { _, local in local }
            loadedUserId = userId
            isReady = true
            NetworkLogStore.shared.logUIEvent("mylist_index_loaded user=\(userId) ids=\(statuses.count)")
        } catch {
            // Keep the previous map: stale statuses beat dropping the filter
            // and showing the user titles they already track.
            NetworkLogStore.shared.logAppError("mylist_index_failed \(error.localizedDescription)")
        }
    }

    private func reset() {
        loadTask?.cancel()
        loadTask = nil
        statuses = [:]
        loadedUserId = nil
        isReady = false
    }
}
