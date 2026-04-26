//
//  SearchViewModel.swift
//  MyShikiPlayer
//
//  Debounced Shikimori search for the ⌘K modal.
//

import Foundation
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published private(set) var results: [AnimeListItem] = []
    @Published private(set) var isSearching: Bool = false
    /// Latest successful request time in milliseconds — shown in the footer.
    @Published private(set) var elapsedMs: Int?

    private let configuration: ShikimoriConfiguration?
    private var debounceTask: Task<Void, Never>?
    private var requestTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    init(configuration: ShikimoriConfiguration?) {
        self.configuration = configuration
        $query
            .removeDuplicates()
            .sink { [weak self] q in self?.schedule(q) }
            .store(in: &cancellables)
    }

    func cancel() {
        debounceTask?.cancel()
        requestTask?.cancel()
    }

    private func schedule(_ raw: String) {
        debounceTask?.cancel()
        let q = raw.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            requestTask?.cancel()
            results = []
            elapsedMs = nil
            isSearching = false
            return
        }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await self?.perform(q)
        }
    }

    private func perform(_ q: String) async {
        requestTask?.cancel()
        guard let configuration else { return }
        isSearching = true
        let started = Date()
        let task = Task { [weak self] in
            let rest = ShikimoriRESTClient(configuration: configuration)
            var query = AnimeListQuery()
            query.search = q
            query.limit = 10
            do {
                let items = try await rest.animes(query: query)
                if Task.isCancelled { return }
                await MainActor.run {
                    guard let self else { return }
                    self.results = items
                    self.elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
                    self.isSearching = false
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    guard let self else { return }
                    self.results = []
                    self.isSearching = false
                    NetworkLogStore.shared.logAppError("search_failed q=\(q) \(error.localizedDescription)")
                }
            }
        }
        requestTask = task
    }
}
