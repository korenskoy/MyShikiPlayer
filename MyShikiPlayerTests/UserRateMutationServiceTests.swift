//
//  UserRateMutationServiceTests.swift
//  MyShikiPlayerTests
//
//  Drives `UserRateMutationService` through `MockURLProtocol` so each
//  mutation branch (create / update / delete / favorite toggle) is
//  exercised end-to-end at the request shape level. Cache-event posting
//  is observed via `NotificationCenter`.
//

import Foundation
import Testing
@testable import MyShikiPlayer

/// Dedicated `URLProtocol` for this suite. Without it, tests would share
/// `MutationMockURLProtocol.handler` with `ShikimoriHTTPTests` and other suites
/// that also use `MockURLSession.make()` — `.serialized` only restricts
/// concurrency within a single suite, so cross-suite races would clobber
/// the static handler under parallel test execution.
final class MutationMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MutationMockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

@MainActor
@Suite("UserRateMutationService", .serialized)
struct UserRateMutationServiceTests {
    private static let configuration: ShikimoriConfiguration = .testing(
        apiBaseURL: URL(string: "https://api.test")!,
        accessToken: "tok"
    )

    private static func makeService() -> UserRateMutationService {
        UserRateMutationService(session: MutationMockURLProtocol.makeSession())
    }

    /// Builds a synthetic UserRateV2 JSON body for the mock REST handler.
    /// Mirrors the snake_case shape Shikimori actually returns.
    private static func userRateJSON(
        id: Int = 1,
        userId: Int = 1,
        targetId: Int = 1,
        score: Int = 0,
        status: String = "planned",
        episodes: Int = 0
    ) -> Data {
        let json = """
        {
          "id": \(id),
          "user_id": \(userId),
          "target_id": \(targetId),
          "target_type": "Anime",
          "score": \(score),
          "status": "\(status)",
          "episodes": \(episodes),
          "chapters": 0,
          "volumes": 0,
          "text": null,
          "text_html": null,
          "rewatches": 0,
          "created_at": "2026-05-06T12:00:00Z",
          "updated_at": "2026-05-06T12:00:00Z"
        }
        """
        return Data(json.utf8)
    }

    // MARK: - createUserRate

    @Test func createUserRatePostsCorrectBodyAndReturnsResult() async throws {
        let service = Self.makeService()
        var capturedMethod: String?
        var capturedPath: String?
        var capturedBody: [String: Any]?
        MutationMockURLProtocol.handler = { req in
            capturedMethod = req.httpMethod
            capturedPath = req.url?.path
            let data = req.mshpInterceptedBody()
            if !data.isEmpty {
                capturedBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            let body = Self.userRateJSON(
                id: 777, userId: 12, targetId: 50,
                score: 8, status: "watching", episodes: 5
            )
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { MutationMockURLProtocol.handler = nil }

        let result = try await service.createUserRate(
            configuration: Self.configuration,
            animeId: 50,
            userId: 12,
            status: "watching",
            score: 8,
            episodesWatched: 5
        )

        #expect(capturedMethod == "POST")
        #expect(capturedPath == "/api/v2/user_rates")
        let userRate = capturedBody?["user_rate"] as? [String: Any]
        #expect(userRate?["status"] as? String == "watching")
        #expect(userRate?["target_id"] as? String == "50")
        #expect(userRate?["target_type"] as? String == "Anime")
        #expect(userRate?["user_id"] as? String == "12")
        #expect(userRate?["score"] as? String == "8")
        #expect(userRate?["episodes"] as? String == "5")
        #expect(result == UserRateMutationResult(rateId: 777, status: "watching", score: 8, episodesWatched: 5))
    }

    @Test func createUserRateOmitsNilFieldsFromBody() async throws {
        let service = Self.makeService()
        var capturedBody: [String: Any]?
        MutationMockURLProtocol.handler = { req in
            let data = req.mshpInterceptedBody()
            if !data.isEmpty {
                capturedBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (resp, Self.userRateJSON())
        }
        defer { MutationMockURLProtocol.handler = nil }

        _ = try await service.createUserRate(
            configuration: Self.configuration,
            animeId: 1,
            userId: 1,
            status: "planned",
            score: nil,
            episodesWatched: nil
        )

        let userRate = capturedBody?["user_rate"] as? [String: Any]
        // JSONEncoder omits nil Optionals → fields are absent (not "null").
        #expect(userRate?["score"] == nil)
        #expect(userRate?["episodes"] == nil)
    }

    // MARK: - updateUserRate

    @Test func updateUserRatePatchesAndReturnsServerState() async throws {
        let service = Self.makeService()
        var capturedMethod: String?
        var capturedPath: String?
        var capturedBody: [String: Any]?
        MutationMockURLProtocol.handler = { req in
            capturedMethod = req.httpMethod
            capturedPath = req.url?.path
            let data = req.mshpInterceptedBody()
            if !data.isEmpty {
                capturedBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            let body = Self.userRateJSON(
                id: 42, userId: 12, targetId: 50,
                score: 9, status: "completed", episodes: 12
            )
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { MutationMockURLProtocol.handler = nil }

        let result = try await service.updateUserRate(
            configuration: Self.configuration,
            animeId: 50,
            userId: 12,
            rateId: 42,
            status: "completed",
            score: 9,
            episodesWatched: 12
        )

        #expect(capturedMethod == "PATCH")
        #expect(capturedPath == "/api/v2/user_rates/42")
        let userRate = capturedBody?["user_rate"] as? [String: Any]
        #expect(userRate?["status"] as? String == "completed")
        #expect(userRate?["score"] as? String == "9")
        #expect(userRate?["episodes"] as? String == "12")
        // PATCH body should not carry the create-only target identity.
        #expect(userRate?["target_id"] == nil)
        #expect(userRate?["target_type"] == nil)
        #expect(userRate?["user_id"] == nil)
        #expect(result == UserRateMutationResult(rateId: 42, status: "completed", score: 9, episodesWatched: 12))
    }

    @Test func updateUserRateNilStatusPatchesWithoutStatusField() async throws {
        // markEpisodeWatched path: PATCH episodes only, status preserved by
        // the server. Our service must NOT translate this into a DELETE
        // (that would mass-evict the rate).
        let service = Self.makeService()
        var capturedMethod: String?
        var capturedBody: [String: Any]?
        MutationMockURLProtocol.handler = { req in
            capturedMethod = req.httpMethod
            let data = req.mshpInterceptedBody()
            if !data.isEmpty {
                capturedBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            let body = Self.userRateJSON(
                id: 42, userId: 12, targetId: 50,
                score: 7, status: "watching", episodes: 7
            )
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { MutationMockURLProtocol.handler = nil }

        let result = try await service.updateUserRate(
            configuration: Self.configuration,
            animeId: 50,
            userId: 12,
            rateId: 42,
            status: nil,
            score: nil,
            episodesWatched: 7
        )

        #expect(capturedMethod == "PATCH")
        let userRate = capturedBody?["user_rate"] as? [String: Any]
        #expect(userRate?["status"] == nil)
        #expect(userRate?["score"] == nil)
        #expect(userRate?["episodes"] as? String == "7")
        #expect(result.status == "watching") // server preserved
    }

    // MARK: - deleteUserRate

    @Test func deleteUserRateIssuesDeleteAndPostsRemovedEvent() async throws {
        let service = Self.makeService()
        var capturedMethod: String?
        var capturedPath: String?
        MutationMockURLProtocol.handler = { req in
            capturedMethod = req.httpMethod
            capturedPath = req.url?.path
            let resp = HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        defer { MutationMockURLProtocol.handler = nil }

        let observer = CacheEventObserver(name: .cacheUserRateDidChange)
        defer { observer.invalidate() }

        try await service.deleteUserRate(
            configuration: Self.configuration,
            animeId: 50,
            userId: 12,
            rateId: 42
        )

        #expect(capturedMethod == "DELETE")
        #expect(capturedPath == "/api/v2/user_rates/42")
        // Removal posts a userRate-changed notification with `payload == nil`.
        #expect(observer.lastPayload?.animeId == 50)
        #expect(observer.lastPayload?.userId == 12)
        #expect(observer.lastPayload?.payload == nil)
    }

    // MARK: - toggleFavorite

    @Test func toggleFavoriteAddsWhenCurrentlyNotFavorited() async throws {
        let service = Self.makeService()
        var capturedMethod: String?
        var capturedPath: String?
        MutationMockURLProtocol.handler = { req in
            capturedMethod = req.httpMethod
            capturedPath = req.url?.path
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"success":true}"#.utf8))
        }
        defer { MutationMockURLProtocol.handler = nil }

        let observer = CacheEventObserver(name: .cacheFavoriteDidToggle)
        defer { observer.invalidate() }

        let newState = try await service.toggleFavorite(
            configuration: Self.configuration,
            animeId: 50,
            userId: 12,
            currentlyFavorite: false
        )

        #expect(capturedMethod == "POST")
        #expect(capturedPath == "/api/favorites/Anime/50")
        #expect(newState == true)
        #expect(observer.lastPayload?.animeId == 50)
        #expect(observer.lastPayload?.userId == 12)
    }

    @Test func toggleFavoriteRemovesWhenCurrentlyFavorited() async throws {
        let service = Self.makeService()
        var capturedMethod: String?
        MutationMockURLProtocol.handler = { req in
            capturedMethod = req.httpMethod
            let resp = HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        defer { MutationMockURLProtocol.handler = nil }

        let newState = try await service.toggleFavorite(
            configuration: Self.configuration,
            animeId: 50,
            userId: 12,
            currentlyFavorite: true
        )

        #expect(capturedMethod == "DELETE")
        #expect(newState == false)
    }

    @Test func toggleFavoriteSurfacesNetworkErrorWithoutFlippingState() async throws {
        let service = Self.makeService()
        MutationMockURLProtocol.handler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        defer { MutationMockURLProtocol.handler = nil }

        await #expect(throws: ShikimoriAPIError.self) {
            _ = try await service.toggleFavorite(
                configuration: Self.configuration,
                animeId: 1,
                userId: 1,
                currentlyFavorite: false
            )
        }
    }
}

// MARK: - Cache event observer

/// Captures the most recent `CacheEvents` notification of a given name.
/// Used to assert that mutations post the correct payload to subscribers
/// (Home / Profile / Library repos rely on these for invalidation).
@MainActor
private final class CacheEventObserver {
    struct Captured {
        let animeId: Int
        let userId: Int
        /// Reconstructed from the notification's userInfo dictionary —
        /// `CacheEvents` flattens the payload into individual keys rather
        /// than passing the struct directly. Absent when the publisher
        /// chose not to pass one (e.g. delete path posts only ids).
        let payload: CacheEvents.UserRatePayload?
    }

    private(set) var lastPayload: Captured?
    private var token: NSObjectProtocol?

    init(name: Notification.Name) {
        // `queue: nil` invokes the block synchronously on the posting thread
        // — required for the test to read `lastPayload` immediately after
        // the awaited mutation completes. With `queue: .main`, the block is
        // dispatched async even when already on main, so the test races.
        token = NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: nil
        ) { [weak self] note in
            let info = note.userInfo ?? [:]
            let animeId = (info[CacheEvents.animeIdKey] as? Int) ?? -1
            let userId = (info[CacheEvents.userIdKey] as? Int) ?? -1
            let payload: CacheEvents.UserRatePayload? = {
                guard
                    let rateId = info[CacheEvents.rateIdKey] as? Int,
                    let status = info[CacheEvents.statusKey] as? String,
                    let score = info[CacheEvents.scoreKey] as? Int,
                    let episodes = info[CacheEvents.episodesKey] as? Int
                else { return nil }
                return CacheEvents.UserRatePayload(
                    rateId: rateId,
                    status: status,
                    score: score,
                    episodes: episodes,
                    updatedAt: info[CacheEvents.updatedAtKey] as? Date
                )
            }()
            // The post originates from `@MainActor` mutation paths so we are
            // already on the main thread — assume isolation to write the
            // captured value without an extra hop.
            MainActor.assumeIsolated {
                self?.lastPayload = Captured(animeId: animeId, userId: userId, payload: payload)
            }
        }
    }

    func invalidate() {
        if let token { NotificationCenter.default.removeObserver(token) }
    }
}
