//
//  RepositoryNetworkTests.swift
//  MyShikiPlayerTests
//
//  Drives `HistoryRepo` and `AnimeDetailRepo` end-to-end over `MockURLProtocol`,
//  now that both take an injectable `session` and `diskFilename`. Covers the
//  three behaviours the repos exist for: a fetch populates the cache, a repeat
//  call is served without touching the network, and a failed refresh never
//  destroys what was already cached — the last one is a project rule, not a
//  nicety (transient failures must not lose data).
//
//  Everything here shares the process-wide `NotificationCenter` through
//  `CacheEvents`, which is why the suites sit under one serialized parent —
//  see the note on `RepositoryCacheBusTests`.
//

import Foundation
import Testing
@testable import MyShikiPlayer

/// Ids picked to be unique across the whole test target. `CacheEvents`
/// broadcasts to every live repo instance, and other suites post mutations for
/// anime 50 / user 12 — a matching id would invalidate the entry under test and
/// cancel its in-flight request (surfacing as `NSURLErrorCancelled`).
private let testAnimeId = 909_090
private let testUserId = 987_654

private let historyPayload = Data("""
[
  {
    "id": 1001,
    "created_at": "2026-01-05T10:00:00.000+03:00",
    "description": "Просмотрен эпизод 3",
    "target": { "id": 909090, "name": "repo_network_title", "russian": "тайтл_теста", "kind": "tv" }
  }
]
""".utf8)

/// Minimal `AnimeDetail`: only `id` and `name` are non-optional. No genres and
/// no franchise on purpose — `loadRelated` / `loadFranchise` then short-circuit
/// and `PosterEnricher.shared` is never asked for anything, so no request can
/// escape to the real network.
private let animeDetailPayload = Data("""
{
  "id": 909090,
  "name": "repo_network_title",
  "russian": "тайтл_теста",
  "kind": "tv",
  "status": "released",
  "episodes": 12,
  "episodes_aired": 12,
  "genres": [],
  "studios": [],
  "videos": [],
  "screenshots": [],
  "user_rate": null
}
""".utf8)

/// Shared between the stub handler (URLSession thread) and the test body
/// (main actor). Reads happen only after the awaited call has completed.
private final class RequestCounter: @unchecked Sendable {
    private(set) var value = 0
    func bump() { value += 1 }
}

/// Stand-in for a short-lived subscriber that unsubscribes by hand.
@MainActor
private final class ClearAllCounter {
    private(set) var hits = 0
    private var token: NSObjectProtocol?

    init() {
        token = CacheEvents.observeClearAll { [weak self] in
            self?.hits += 1
        }
    }

    /// Idempotent, so a `defer` can back up the explicit call in the test.
    func unsubscribe() {
        guard let token else { return }
        NotificationCenter.default.removeObserver(token)
        self.token = nil
    }
}

/// Tally that outlives the subscriber under test.
private final class HitBox: @unchecked Sendable {
    var count = 0
}

/// Subscriber that relies on `CacheObserverBag` rather than unsubscribing by
/// hand — the shape real view models use.
@MainActor
private final class BaggedSubscriber {
    private let bag = CacheObserverBag()

    init(hits: HitBox) {
        bag.add(CacheEvents.observeClearAll { hits.count += 1 })
    }
}

private func stubResponse(_ request: URLRequest, status: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: request.url!,
        statusCode: status,
        httpVersion: nil,
        headerFields: ["Content-Type": "application/json"]
    )!
}

private let testConfiguration: ShikimoriConfiguration = .testing(
    apiBaseURL: URL(string: "https://api.test")!,
    accessToken: "tok"
)

/// `CacheEvents` posts reach every live repo instance in the process, and
/// `cacheShouldClearAll` makes each of them cancel its in-flight tasks. So a
/// subscription test posting that event while a network test has a request open
/// aborts it (`NSURLErrorCancelled`). Serializing the whole group removes the
/// overlap; `.serialized` applies recursively to the nested suites.
@Suite("Repositories over the cache bus", .serialized)
struct RepositoryCacheBusTests {

    // MARK: - HistoryRepo

    @MainActor
    @Suite("HistoryRepo over the network")
    struct HistoryRepoNetworkTests {
        @Test func successfulLoadPopulatesTheCache() async throws {
            let session = MockURLSession.make()
            let filename = "test-history-\(UUID().uuidString).json"
            let repo = HistoryRepo(session: session, diskFilename: filename)
            defer { DiskBackup.remove(filename: filename) }

            let counter = RequestCounter()
            session.mshpMockHandler = { request in
                counter.bump()
                return (stubResponse(request), historyPayload)
            }

            let entries = try await repo.history(configuration: testConfiguration, userId: testUserId)

            #expect(entries.count == 1)
            #expect(entries.first?.id == 1001)
            #expect(entries.first?.target?.id == testAnimeId)
            #expect(counter.value == 1)
            #expect(repo.cachedHistory(userId: testUserId, allowStale: false)?.count == 1)
        }

        @Test func repeatCallIsServedFromCacheWithoutNetwork() async throws {
            let session = MockURLSession.make()
            let filename = "test-history-\(UUID().uuidString).json"
            let repo = HistoryRepo(session: session, diskFilename: filename)
            defer { DiskBackup.remove(filename: filename) }

            let counter = RequestCounter()
            session.mshpMockHandler = { request in
                counter.bump()
                return (stubResponse(request), historyPayload)
            }

            _ = try await repo.history(configuration: testConfiguration, userId: testUserId)
            let second = try await repo.history(configuration: testConfiguration, userId: testUserId)

            #expect(second.count == 1)
            #expect(counter.value == 1)
        }

        @Test func failedRefreshKeepsTheCachedHistory() async throws {
            let session = MockURLSession.make()
            let filename = "test-history-\(UUID().uuidString).json"
            let repo = HistoryRepo(session: session, diskFilename: filename)
            defer { DiskBackup.remove(filename: filename) }

            session.mshpMockHandler = { request in (stubResponse(request), historyPayload) }
            _ = try await repo.history(configuration: testConfiguration, userId: testUserId)

            session.mshpMockHandler = { _ in throw URLError(.notConnectedToInternet) }
            do {
                _ = try await repo.history(
                    configuration: testConfiguration,
                    userId: testUserId,
                    forceRefresh: true
                )
                Issue.record("Expected the forced refresh to fail")
            } catch {
                // Expected — the point is what survives it.
            }

            #expect(repo.cachedHistory(userId: testUserId, allowStale: true)?.count == 1)
            #expect(repo.cachedHistory(userId: testUserId, allowStale: false)?.first?.id == 1001)
        }
    }

    // MARK: - AnimeDetailRepo

    @MainActor
    @Suite("AnimeDetailRepo over the network")
    struct AnimeDetailRepoNetworkTests {
        /// GraphQL stats and the Kodik search are optional for a snapshot, so
        /// answering everything unrecognised with 404 exercises the
        /// "piece missing" path instead of leaking a real request.
        private static func route(_ request: URLRequest) -> (HTTPURLResponse, Data) {
            switch request.url?.path ?? "" {
            case "/api/animes/\(testAnimeId)":
                return (stubResponse(request), animeDetailPayload)
            case "/api/animes/\(testAnimeId)/screenshots", "/api/animes/\(testAnimeId)/videos":
                return (stubResponse(request), Data("[]".utf8))
            default:
                return (stubResponse(request, status: 404), Data("{}".utf8))
            }
        }

        @Test func successfulSnapshotPopulatesTheCache() async throws {
            let session = MockURLSession.make()
            let filename = "test-anime-detail-\(UUID().uuidString).json"
            let repo = AnimeDetailRepo(session: session, diskFilename: filename)
            defer { DiskBackup.remove(filename: filename) }

            let counter = RequestCounter()
            session.mshpMockHandler = { request in
                if request.url?.path == "/api/animes/\(testAnimeId)" { counter.bump() }
                return Self.route(request)
            }

            let snapshot = try await repo.snapshot(
                id: testAnimeId,
                configuration: testConfiguration,
                kodikClient: KodikClient(session: session)
            )

            #expect(snapshot.detail.id == testAnimeId)
            #expect(snapshot.detail.name == "repo_network_title")
            #expect(snapshot.related.isEmpty)
            #expect(snapshot.franchiseItems.isEmpty)
            #expect(counter.value == 1)
            #expect(repo.cachedSnapshot(id: testAnimeId, allowStale: false)?.detail.id == testAnimeId)
        }

        @Test func repeatSnapshotIsServedFromCacheWithoutNetwork() async throws {
            let session = MockURLSession.make()
            let filename = "test-anime-detail-\(UUID().uuidString).json"
            let repo = AnimeDetailRepo(session: session, diskFilename: filename)
            defer { DiskBackup.remove(filename: filename) }

            let counter = RequestCounter()
            session.mshpMockHandler = { request in
                if request.url?.path == "/api/animes/\(testAnimeId)" { counter.bump() }
                return Self.route(request)
            }

            let client = KodikClient(session: session)
            _ = try await repo.snapshot(id: testAnimeId, configuration: testConfiguration, kodikClient: client)
            let second = try await repo.snapshot(id: testAnimeId, configuration: testConfiguration, kodikClient: client)

            #expect(second.detail.id == testAnimeId)
            #expect(counter.value == 1)
        }

        @Test func failedRefreshKeepsTheCachedSnapshot() async throws {
            let session = MockURLSession.make()
            let filename = "test-anime-detail-\(UUID().uuidString).json"
            let repo = AnimeDetailRepo(session: session, diskFilename: filename)
            defer { DiskBackup.remove(filename: filename) }

            session.mshpMockHandler = { request in Self.route(request) }
            let client = KodikClient(session: session)
            _ = try await repo.snapshot(id: testAnimeId, configuration: testConfiguration, kodikClient: client)

            session.mshpMockHandler = { _ in throw URLError(.notConnectedToInternet) }
            do {
                _ = try await repo.snapshot(
                    id: testAnimeId,
                    configuration: testConfiguration,
                    kodikClient: client,
                    forceRefresh: true
                )
                Issue.record("Expected the forced refresh to fail")
            } catch {
                // Expected — the point is what survives it.
            }

            #expect(repo.cachedSnapshot(id: testAnimeId, allowStale: true)?.detail.id == testAnimeId)
            #expect(repo.cachedSnapshot(id: testAnimeId, allowStale: false)?.detail.name == "repo_network_title")
        }
    }

    // MARK: - Subscription teardown

    @MainActor
    @Suite("CacheEvents subscriptions")
    struct CacheEventsSubscriptionTests {
        /// Observers are delivered through `OperationQueue.main`, so give the
        /// run loop a chance to drain before asserting.
        private func settle() async throws {
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        @Test func removingTheTokenStopsDelivery() async throws {
            let counter = ClearAllCounter()
            defer { counter.unsubscribe() }

            CacheEvents.postClearAllCaches()
            try await settle()
            #expect(counter.hits == 1)

            counter.unsubscribe()
            let baseline = counter.hits
            CacheEvents.postClearAllCaches()
            try await settle()
            // A delta, not an absolute: what matters is "nothing more arrived",
            // and that stays true regardless of who else posts.
            #expect(counter.hits == baseline)
        }

        @Test func bagUnsubscribesWhenTheOwnerIsDeallocated() async throws {
            let hits = HitBox()
            var subscriber: BaggedSubscriber? = BaggedSubscriber(hits: hits)
            #expect(subscriber != nil)

            CacheEvents.postClearAllCaches()
            try await settle()
            #expect(hits.count == 1)

            subscriber = nil
            let baseline = hits.count
            CacheEvents.postClearAllCaches()
            try await settle()
            #expect(hits.count == baseline)
        }
    }
}
