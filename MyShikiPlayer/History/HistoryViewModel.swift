//
//  HistoryViewModel.swift
//  MyShikiPlayer
//
//  State for the History screen. A thin layer: subscription to the local
//  journal + loading remote pages via HistoryRepo + merging via
//  HistoryMerger. No networking logic lives here.
//

import Foundation
import Combine

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published private(set) var items: [MergedHistoryItem] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var hasMore: Bool = true
    /// Banner "failed to load the server part". The local part stays
    /// visible regardless — see goal: resilience to network errors.
    @Published private(set) var remoteErrorMessage: String?

    private var remoteEntries: [UserHistoryEntry] = []
    private var loadedPage = 1
    private var historyStoreSubscription: AnyCancellable?

    init() {
        // Local event → redraw instantly (no network request).
        // Without this, an episode just finished would only appear in
        // history after the next reload.
        historyStoreSubscription = WatchHistoryStore.shared.$events
            .sink { [weak self] _ in
                self?.recomputeItems()
            }
    }

    // MARK: - Loading

    func reload(
        configuration: ShikimoriConfiguration?,
        userId: Int?,
        forceRefresh: Bool = false
    ) async {
        // SWR: show the cache immediately, no spinner.
        if let userId, let cached = HistoryRepo.shared.cachedHistory(userId: userId, allowStale: true) {
            remoteEntries = cached
            recomputeItems()
        } else {
            // We still show the local part — the merge doesn't depend on the network.
            recomputeItems()
            isLoading = true
        }
        remoteErrorMessage = nil

        guard let configuration, let userId else {
            isLoading = false
            return
        }

        do {
            let entries = try await HistoryRepo.shared.history(
                configuration: configuration,
                userId: userId,
                forceRefresh: forceRefresh
            )
            remoteEntries = entries
            loadedPage = 1
            hasMore = !entries.isEmpty
            recomputeItems()
        } catch {
            // Don't tear down the session — this is exactly the case the memory rule forbids.
            // Just show a banner. The local history is already on screen.
            remoteErrorMessage = error.localizedDescription
            NetworkLogStore.shared.logAppError(
                "history_remote_failed err=\(error.localizedDescription)"
            )
        }
        isLoading = false
    }

    func loadMore(configuration: ShikimoriConfiguration, userId: Int) async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        let nextPage = loadedPage + 1
        do {
            let page = try await HistoryRepo.shared.historyPage(
                configuration: configuration,
                userId: userId,
                page: nextPage
            )
            if page.isEmpty {
                hasMore = false
            } else {
                remoteEntries.append(contentsOf: page)
                loadedPage = nextPage
                recomputeItems()
            }
        } catch {
            remoteErrorMessage = error.localizedDescription
            NetworkLogStore.shared.logAppError(
                "history_loadmore_failed page=\(nextPage) err=\(error.localizedDescription)"
            )
        }
        isLoadingMore = false
    }

    // MARK: - Mutation

    /// Removes from the local journal all events that were collapsed into
    /// the given item. Remote events are left alone — we have no control
    /// over them on the server anyway.
    func removeLocal(item: MergedHistoryItem) {
        let ids = item.localEventIds
        guard !ids.isEmpty else { return }
        for id in ids {
            WatchHistoryStore.shared.remove(eventId: id)
        }
        // recomputeItems will fire via the subscription to $events.
    }

    // MARK: - Private

    private func recomputeItems() {
        items = HistoryMerger.merge(
            local: WatchHistoryStore.shared.events,
            remote: remoteEntries
        )
    }
}
