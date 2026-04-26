//
//  ShikimoriRESTClient.swift
//  MyShikiPlayer
//

import Foundation

final class ShikimoriRESTClient: Sendable {
    private let http: ShikimoriHTTPClient
    private let apiBase: URL

    init(configuration: ShikimoriConfiguration, session: URLSession = .shared) {
        self.http = ShikimoriHTTPClient(configuration: configuration, session: session)
        self.apiBase = configuration.apiBaseURL
    }

    private static var restDecoder: JSONDecoder {
        let d = ShikimoriJSON.decoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private static var userRateEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }

    // MARK: - v1

    func animes(query: AnimeListQuery = AnimeListQuery()) async throws -> [AnimeListItem] {
        var c = URLComponents(url: apiBase.appendingPathComponent("api/animes"), resolvingAgainstBaseURL: false)!
        let items = query.queryItems()
        if !items.isEmpty { c.queryItems = items }
        guard let url = c.url else { throw ShikimoriAPIError.invalidURL }
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode([AnimeListItem].self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    /// Adds an anime to favourites. Shikimori responds with `{"success":true}`; we only care about 2xx.
    func addFavorite(animeId: Int) async throws {
        let url = apiBase.appendingPathComponent("api/favorites/Anime/\(animeId)")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "POST")
        try Self.throwIfNeeded(httpResp, data: data, acceptable: [200, 201])
    }

    /// Removes an anime from favourites.
    func removeFavorite(animeId: Int) async throws {
        let url = apiBase.appendingPathComponent("api/favorites/Anime/\(animeId)")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "DELETE")
        try Self.throwIfNeeded(httpResp, data: data, acceptable: [200, 204])
    }

    /// Full list of screenshots. REST `/api/animes/{id}` returns only 2,
    /// while this endpoint returns all of them.
    func animeScreenshots(id: Int) async throws -> [AnimeScreenshotREST] {
        let url = apiBase.appendingPathComponent("api/animes/\(id)/screenshots")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode([AnimeScreenshotREST].self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    /// Schedule of ongoings with `next_episode_at`. Shikimori returns a single
    /// global list with no parameters — filtering/grouping by day is done on the client.
    func calendar() async throws -> [CalendarEntry] {
        let url = apiBase.appendingPathComponent("api/calendar")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode([CalendarEntry].self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    /// Full list of videos/trailers (similarly — a separate endpoint).
    func animeVideos(id: Int) async throws -> [AnimeVideoREST] {
        let url = apiBase.appendingPathComponent("api/animes/\(id)/videos")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode([AnimeVideoREST].self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    func anime(id: Int) async throws -> AnimeDetail {
        let url = apiBase.appendingPathComponent("api/animes/\(id)")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode(AnimeDetail.self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    /// Full user profile (stats, common_info, etc.).
    func userProfile(id: Int) async throws -> UserProfile {
        let url = apiBase.appendingPathComponent("api/users/\(id)")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode(UserProfile.self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    /// User history: views, status changes, scores.
    /// `targetType` = "Anime" (or "Manga") filters to only anime events.
    func userHistory(
        id: Int,
        targetType: String? = "Anime",
        limit: Int = 20,
        page: Int = 1
    ) async throws -> [UserHistoryEntry] {
        var c = URLComponents(url: apiBase.appendingPathComponent("api/users/\(id)/history"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        if let targetType, !targetType.isEmpty {
            items.append(URLQueryItem(name: "target_type", value: targetType))
        }
        c.queryItems = items
        guard let url = c.url else { throw ShikimoriAPIError.invalidURL }
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode([UserHistoryEntry].self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    /// User's friends.
    func userFriends(id: Int) async throws -> [UserFriend] {
        let url = apiBase.appendingPathComponent("api/users/\(id)/friends")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode([UserFriend].self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    /// User's favourites (animes / mangas / characters / …). We only care about animes.
    func userFavourites(id: Int) async throws -> UserFavourites {
        let url = apiBase.appendingPathComponent("api/users/\(id)/favourites")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode(UserFavourites.self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    // MARK: - Social (topics + comments)

    /// Topic feed. `forum` defaults to `animanga` — the category closest to us
    /// (anime + manga). Empty parameters are dropped, since Shikimori sometimes
    /// fails on empty values.
    func topics(forum: String? = "animanga", limit: Int = 30, page: Int = 1) async throws -> [Topic] {
        var c = URLComponents(url: apiBase.appendingPathComponent("api/topics"), resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        if let forum, !forum.isEmpty {
            items.append(URLQueryItem(name: "forum", value: forum))
        }
        c.queryItems = items
        guard let url = c.url else { throw ShikimoriAPIError.invalidURL }
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode([Topic].self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    /// Full topic (includes html_body, forum, linked).
    func topic(id: Int) async throws -> Topic {
        let url = apiBase.appendingPathComponent("api/topics/\(id)")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode(Topic.self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    /// Comments for an object. `type` is usually `"Topic"`, but may also be
    /// `"Review"`, `"User"`, or `"Anime"`. Shikimori returns `desc=true` by default.
    func comments(
        commentableType: String,
        commentableId: Int,
        limit: Int = 30,
        page: Int = 1
    ) async throws -> [TopicComment] {
        var c = URLComponents(url: apiBase.appendingPathComponent("api/comments"), resolvingAgainstBaseURL: false)!
        c.queryItems = [
            URLQueryItem(name: "commentable_type", value: commentableType),
            URLQueryItem(name: "commentable_id", value: String(commentableId)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        guard let url = c.url else { throw ShikimoriAPIError.invalidURL }
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode([TopicComment].self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    func whoami() async throws -> CurrentUser {
        let url = apiBase.appendingPathComponent("api/users/whoami")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode(CurrentUser.self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    // MARK: - Reference catalogs

    func genres() async throws -> [Genre] {
        let url = apiBase.appendingPathComponent("api/genres")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            let decoder = ShikimoriJSON.decoder()
            return try decoder.decode([Genre].self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    func studios() async throws -> [Studio] {
        let url = apiBase.appendingPathComponent("api/studios")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            let decoder = ShikimoriJSON.decoder()
            return try decoder.decode([Studio].self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    // MARK: - v2 user_rates

    func userRates(query: UserRatesListQuery = UserRatesListQuery()) async throws -> [UserRateV2] {
        var c = URLComponents(url: apiBase.appendingPathComponent("api/v2/user_rates"), resolvingAgainstBaseURL: false)!
        let items = query.queryItems()
        if !items.isEmpty { c.queryItems = items }
        guard let url = c.url else { throw ShikimoriAPIError.invalidURL }
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode([UserRateV2].self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    func userRate(id: Int) async throws -> UserRateV2 {
        let url = apiBase.appendingPathComponent("api/v2/user_rates/\(id)")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "GET")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode(UserRateV2.self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    func createUserRate(_ body: UserRateV2CreateBody) async throws -> UserRateV2 {
        let url = apiBase.appendingPathComponent("api/v2/user_rates")
        let enc = Self.userRateEncoder
        let payload = try enc.encode(body)
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "POST", jsonBody: payload)
        try Self.throwIfNeeded(httpResp, data: data, acceptable: [200, 201])
        do {
            return try Self.restDecoder.decode(UserRateV2.self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    func updateUserRate(id: Int, body: UserRateV2UpdateBody) async throws -> UserRateV2 {
        let url = apiBase.appendingPathComponent("api/v2/user_rates/\(id)")
        let enc = Self.userRateEncoder
        let payload = try enc.encode(body)
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "PATCH", jsonBody: payload)
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode(UserRateV2.self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    func incrementUserRate(id: Int) async throws -> UserRateV2 {
        let url = apiBase.appendingPathComponent("api/v2/user_rates/\(id)/increment")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "POST")
        try Self.throwIfNeeded(httpResp, data: data)
        do {
            return try Self.restDecoder.decode(UserRateV2.self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
    }

    func deleteUserRate(id: Int) async throws {
        let url = apiBase.appendingPathComponent("api/v2/user_rates/\(id)")
        let (data, httpResp) = try await http.jsonRequest(url: url, method: "DELETE")
        try Self.throwIfNeeded(httpResp, data: data, acceptable: [200, 204])
    }

    private static func throwIfNeeded(_ response: HTTPURLResponse, data: Data, acceptable: Set<Int>? = nil) throws {
        let code = response.statusCode
        if let acceptable {
            guard acceptable.contains(code) else {
                throw ShikimoriAPIError.httpStatus(code: code, body: data.isEmpty ? nil : data)
            }
            return
        }
        guard (200..<300).contains(code) else {
            throw ShikimoriAPIError.httpStatus(code: code, body: data.isEmpty ? nil : data)
        }
    }
}
