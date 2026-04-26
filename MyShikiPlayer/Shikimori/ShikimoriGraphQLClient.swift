//
//  ShikimoriGraphQLClient.swift
//  MyShikiPlayer
//

import Foundation

private struct GraphQLRequestBody<Variables: Encodable>: Encodable {
    let query: String
    let variables: Variables
}

private struct GraphQLRequestBodyNoVariables: Encodable {
    let query: String
}

private struct GraphQLEnumIntrospectionEnvelope: Decodable {
    struct DataField: Decodable {
        struct TypeField: Decodable {
            struct EnumValue: Decodable {
                let name: String
            }
            let enumValues: [EnumValue]?
        }
        let typeField: TypeField?

        enum CodingKeys: String, CodingKey {
            case typeField = "__type"
        }
    }
    let data: DataField?
    let errors: [GraphQLErrorMessage]?
}

private struct GraphQLDynamicAnimesEnvelope: Decodable {
    struct DataField: Decodable {
        let animes: [GraphQLAnimeSummary]?
    }
    let data: DataField?
    let errors: [GraphQLErrorMessage]?
}

final class ShikimoriGraphQLClient: Sendable {
    private let http: ShikimoriHTTPClient
    private let graphqlURL: URL

    init(configuration: ShikimoriConfiguration, session: URLSession = .shared) {
        self.http = ShikimoriHTTPClient(configuration: configuration, session: session)
        self.graphqlURL = configuration.apiBaseURL.appendingPathComponent("api/graphql")
    }

    private static var gqlDecoder: JSONDecoder {
        let d = ShikimoriJSON.decoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }

    private static var gqlEncoder: JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .useDefaultKeys
        return e
    }

    func animes(search: String, limit: Int, kind: String? = nil) async throws -> [GraphQLAnimeSummary] {
        let vars = AnimesSearchVariables(search: search, limit: limit, kind: kind)
        let body = GraphQLRequestBody(query: ShikimoriGraphQLQueries.animesSearch, variables: vars)
        let payload = try Self.gqlEncoder.encode(body)
        let (data, httpResp) = try await http.jsonRequest(url: graphqlURL, method: "POST", jsonBody: payload)
        guard (200..<300).contains(httpResp.statusCode) else {
            throw ShikimoriAPIError.httpStatus(code: httpResp.statusCode, body: data.isEmpty ? nil : data)
        }
        let envelope: GraphQLAnimesEnvelope
        do {
            envelope = try Self.gqlDecoder.decode(GraphQLAnimesEnvelope.self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
        if let errs = envelope.errors, !errs.isEmpty {
            throw ShikimoriAPIError.graphqlErrors(errs)
        }
        return envelope.data?.animes ?? []
    }

    func animes(ids: [Int], search: String? = nil, limit: Int, kind: AnimeKindString? = nil) async throws -> [GraphQLAnimeSummary] {
        let vars = AnimesByIdsVariables(
            ids: ids.isEmpty ? nil : ids.map(String.init).joined(separator: ","),
            search: search,
            limit: limit,
            kind: kind
        )
        let body = GraphQLRequestBody(query: ShikimoriGraphQLQueries.animesByIds, variables: vars)
        let payload = try Self.gqlEncoder.encode(body)
        let (data, httpResp) = try await http.jsonRequest(url: graphqlURL, method: "POST", jsonBody: payload)
        guard (200..<300).contains(httpResp.statusCode) else {
            throw ShikimoriAPIError.httpStatus(code: httpResp.statusCode, body: data.isEmpty ? nil : data)
        }
        let envelope: GraphQLAnimesEnvelope
        do {
            envelope = try Self.gqlDecoder.decode(GraphQLAnimesEnvelope.self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
        if let errs = envelope.errors, !errs.isEmpty {
            throw ShikimoriAPIError.graphqlErrors(errs)
        }
        return envelope.data?.animes ?? []
    }

    /// Community statistics for a title: distribution of scores and statuses.
    /// Returns nil if GraphQL returned an empty result — the UI simply hides the block.
    func animeStats(id: Int) async throws -> GraphQLAnimeStatsEntry? {
        let vars = AnimeStatsVariables(id: String(id))
        let body = GraphQLRequestBody(query: ShikimoriGraphQLQueries.animeStats, variables: vars)
        let payload = try Self.gqlEncoder.encode(body)
        let (data, httpResp) = try await http.jsonRequest(url: graphqlURL, method: "POST", jsonBody: payload)
        guard (200..<300).contains(httpResp.statusCode) else {
            throw ShikimoriAPIError.httpStatus(code: httpResp.statusCode, body: data.isEmpty ? nil : data)
        }
        let envelope: GraphQLAnimeStatsEnvelope
        do {
            envelope = try Self.gqlDecoder.decode(GraphQLAnimeStatsEnvelope.self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
        if let errs = envelope.errors, !errs.isEmpty {
            throw ShikimoriAPIError.graphqlErrors(errs)
        }
        return envelope.data?.animes?.first
    }

    func currentUser() async throws -> CurrentUser {
        // Try the previously-known-good query shape first to avoid wasting
        // 1-2 round-trips per cold start re-discovering it. Shikimori's
        // `User` schema occasionally drops fields (e.g. `image`, `avatar`),
        // so we still fall back to the full candidate list on first failure.
        let queries = Self.orderedCandidates(preferred: Self.cachedCurrentUserQuery)
        do {
            let (user, query) = try await firstWorkingCurrentUserQuery(in: queries)
            Self.cacheCurrentUserQuery(query)
            return user
        } catch {
            // None of the candidates worked — clear the memoised pick so we
            // don't keep starting from a dead one next launch.
            Self.cacheCurrentUserQuery(nil)
            throw error
        }
    }

    private func firstWorkingCurrentUserQuery(
        in queries: [String]
    ) async throws -> (CurrentUser, String) {
        var lastError: Error?
        for query in queries {
            do {
                return (try await currentUser(using: query), query)
            } catch let err as ShikimoriAPIError {
                lastError = err
                if case .graphqlErrors(let gqlErrors) = err, Self.isUnknownFieldError(gqlErrors) {
                    continue
                }
                throw err
            } catch {
                throw error
            }
        }
        throw lastError ?? ShikimoriAPIError.invalidResponse
    }

    private static let currentUserQueryDefaultsKey = "shikimori.gql.currentUserQuery"

    private static var cachedCurrentUserQuery: String? {
        UserDefaults.standard.string(forKey: currentUserQueryDefaultsKey)
    }

    private static func cacheCurrentUserQuery(_ query: String?) {
        if let query, currentUserQueryCandidates.contains(query) {
            UserDefaults.standard.set(query, forKey: currentUserQueryDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentUserQueryDefaultsKey)
        }
    }

    private static func orderedCandidates(preferred: String?) -> [String] {
        let candidates = currentUserQueryCandidates
        guard let preferred, candidates.contains(preferred) else { return candidates }
        var ordered: [String] = [preferred]
        ordered.append(contentsOf: candidates.filter { $0 != preferred })
        return ordered
    }

    private func currentUser(using query: String) async throws -> CurrentUser {
        let body = GraphQLRequestBodyNoVariables(query: query)
        let payload = try Self.gqlEncoder.encode(body)
        let (data, httpResp) = try await http.jsonRequest(url: graphqlURL, method: "POST", jsonBody: payload)
        guard (200..<300).contains(httpResp.statusCode) else {
            throw ShikimoriAPIError.httpStatus(code: httpResp.statusCode, body: data.isEmpty ? nil : data)
        }
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
        guard let json = jsonObject as? [String: Any] else { throw ShikimoriAPIError.invalidResponse }
        if let errorsRaw = json["errors"] as? [[String: Any]], !errorsRaw.isEmpty {
            let errors = errorsRaw.compactMap { dict -> GraphQLErrorMessage? in
                guard let message = dict["message"] as? String else { return nil }
                return GraphQLErrorMessage(message: message)
            }
            throw ShikimoriAPIError.graphqlErrors(errors)
        }
        guard
            let dataField = json["data"] as? [String: Any],
            let user = dataField["currentUser"] as? [String: Any]
        else {
            throw ShikimoriAPIError.invalidResponse
        }
        let idValue = user["id"]
        let userId: Int
        if let idString = idValue as? String, let parsed = Int(idString) {
            userId = parsed
        } else if let idInt = idValue as? Int {
            userId = idInt
        } else {
            throw ShikimoriAPIError.invalidResponse
        }
        let nickname = user["nickname"] as? String ?? ""
        if nickname.isEmpty {
            throw ShikimoriAPIError.invalidResponse
        }

        let imageObject = user["image"] as? [String: Any]
        let imageSet = UserImageSet(
            x160: imageObject?["x160"] as? String,
            x148: imageObject?["x148"] as? String,
            x80: imageObject?["x80"] as? String,
            x64: imageObject?["x64"] as? String,
            x48: imageObject?["x48"] as? String,
            x32: imageObject?["x32"] as? String,
            x16: imageObject?["x16"] as? String
        )
        let avatar = (user["avatarUrl"] as? String) ?? (user["avatar"] as? String)

        return CurrentUser(
            id: userId,
            nickname: nickname,
            avatar: avatar,
            image: imageObject == nil ? nil : imageSet,
            lastOnlineAt: nil,
            url: nil,
            name: nil,
            sex: nil,
            website: nil,
            birthOn: nil,
            fullYears: nil,
            locale: nil
        )
    }

    private static var currentUserQueryCandidates: [String] {
        [
            """
            query CurrentUser {
              currentUser {
                id
                nickname
                avatarUrl
                image { x160 x148 x80 x64 x48 x32 x16 }
              }
            }
            """,
            """
            query CurrentUser {
              currentUser {
                id
                nickname
                avatar
                image { x160 x148 x80 x64 x48 x32 x16 }
              }
            }
            """,
            """
            query CurrentUser {
              currentUser {
                id
                nickname
                avatarUrl
              }
            }
            """,
            """
            query CurrentUser {
              currentUser {
                id
                nickname
                avatar
              }
            }
            """,
            """
            query CurrentUser {
              currentUser {
                id
                nickname
              }
            }
            """,
        ]
    }

    private static func isUnknownFieldError(_ errors: [GraphQLErrorMessage]) -> Bool {
        errors.contains { error in
            let message = error.message.lowercased()
            return message.contains("field") && (message.contains("doesn't exist") || message.contains("unknown"))
        }
    }

    func enumValues(typeName: String) async throws -> [String] {
        let sanitized = typeName.filter { $0.isLetter || $0.isNumber || $0 == "_" }
        guard !sanitized.isEmpty else { return [] }
        let query = """
        query EnumValues {
          __type(name: "\(sanitized)") {
            enumValues { name }
          }
        }
        """
        let body = GraphQLRequestBodyNoVariables(query: query)
        let payload = try Self.gqlEncoder.encode(body)
        let (data, httpResp) = try await http.jsonRequest(url: graphqlURL, method: "POST", jsonBody: payload)
        guard (200..<300).contains(httpResp.statusCode) else {
            throw ShikimoriAPIError.httpStatus(code: httpResp.statusCode, body: data.isEmpty ? nil : data)
        }
        let envelope: GraphQLEnumIntrospectionEnvelope
        do {
            envelope = try Self.gqlDecoder.decode(GraphQLEnumIntrospectionEnvelope.self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
        if let errs = envelope.errors, !errs.isEmpty {
            throw ShikimoriAPIError.graphqlErrors(errs)
        }
        return envelope.data?.typeField?.enumValues?.map(\.name) ?? []
    }

    func animesByIdsDynamic(
        ids: [Int],
        search: String?,
        kindRaw: String?,
        ratingRaw: String?,
        season: String?
    ) async throws -> [GraphQLAnimeSummary] {
        // Keep this static to avoid deep schema-introspection query depth limits.
        let argTypes: [String: String] = [
            "ids": "String",
            "limit": "Int",
            "search": "String",
            "kind": "AnimeKindString",
            "rating": "AnimeRatingString",
            "season": "String",
        ]

        var variables: [String: Any] = [:]
        var variableDefinitions: [String] = []
        var argumentBindings: [String] = []

        func addVar(_ name: String, value: Any?, typeName: String?) {
            guard let value, let typeName else { return }
            variables[name] = value
            variableDefinitions.append("$\(name): \(typeName)")
            argumentBindings.append("\(name): $\(name)")
        }

        addVar("ids", value: ids.isEmpty ? nil : ids.map(String.init).joined(separator: ","), typeName: argTypes["ids"])
        addVar("limit", value: ids.count, typeName: argTypes["limit"] ?? "Int")
        addVar("search", value: search, typeName: argTypes["search"])
        addVar("kind", value: kindRaw, typeName: argTypes["kind"])
        addVar("rating", value: ratingRaw, typeName: argTypes["rating"])
        addVar("season", value: season, typeName: argTypes["season"])

        let variablesDecl = variableDefinitions.isEmpty ? "" : "(\(variableDefinitions.joined(separator: ", ")))"
        let argsDecl = argumentBindings.joined(separator: ", ")
        let query = """
        query AnimesDynamic\(variablesDecl) {
          animes(\(argsDecl)) {
            id
            name
            russian
            kind
            status
            season
            airedOn { date }
            releasedOn { date }
            poster { originalUrl mainUrl }
          }
        }
        """

        let body: [String: Any] = [
            "query": query,
            "variables": variables,
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        let (data, httpResp) = try await http.jsonRequest(url: graphqlURL, method: "POST", jsonBody: payload)
        guard (200..<300).contains(httpResp.statusCode) else {
            throw ShikimoriAPIError.httpStatus(code: httpResp.statusCode, body: data.isEmpty ? nil : data)
        }
        let envelope: GraphQLDynamicAnimesEnvelope
        do {
            envelope = try Self.gqlDecoder.decode(GraphQLDynamicAnimesEnvelope.self, from: data)
        } catch {
            throw ShikimoriAPIError.decoding(underlying: error, body: data)
        }
        if let errs = envelope.errors, !errs.isEmpty {
            throw ShikimoriAPIError.graphqlErrors(errs)
        }
        return envelope.data?.animes ?? []
    }
}
