//
//  ShikimoriAPITests.swift
//  MyShikiPlayerTests
//

import Foundation
import Testing
@testable import MyShikiPlayer

private func fixtureData(named name: String, sourceFile: String = #filePath) throws -> Data {
    let url = URL(fileURLWithPath: sourceFile)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/\(name).json")
    return try Data(contentsOf: url)
}

private var restDecoder: JSONDecoder {
    let d = ShikimoriJSON.decoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}

private var gqlDecoder: JSONDecoder {
    let d = ShikimoriJSON.decoder()
    d.keyDecodingStrategy = .useDefaultKeys
    return d
}

/// Unthrottled: tests must not pay the 5 rps gate, nor eat slots from the
/// process-wide rolling window shared with the rest of the suite.
private func unthrottled() -> RequestThrottler {
    RequestThrottler(minInterval: 0, maxRequestsInWindow: .max)
}

private func graphQLConfig() -> ShikimoriConfiguration {
    ShikimoriConfiguration.testing(apiBaseURL: URL(string: "https://api.test")!)
}

/// Asserts `operation` fails with a `ShikimoriAPIError` matching `matching`.
/// `#expect(throws:)` only checks the type — the mapping from transport
/// failure to error case is exactly what these tests are about.
private func expectShikimoriError(
    _ description: String,
    performing operation: () async throws -> Void,
    matching: (ShikimoriAPIError) -> Bool
) async {
    do {
        try await operation()
        Issue.record("Expected \(description), got success")
    } catch let error as ShikimoriAPIError {
        #expect(matching(error), "Expected \(description), got \(error)")
    } catch {
        Issue.record("Expected \(description), got \(error)")
    }
}

/// Collects the request bodies the mock saw, so a test can assert on the
/// order in which query candidates were tried.
private final class SentBodies: @unchecked Sendable {
    private(set) var all: [String] = []

    func append(_ body: String) { all.append(body) }
}

@Suite("Shikimori decoding")
struct ShikimoriDecodingTests {
    @Test func animeDetailFromDocFixture() throws {
        let data = try fixtureData(named: "anime_detail")
        let detail = try restDecoder.decode(AnimeDetail.self, from: data)
        #expect(detail.id == 50)
        #expect(detail.name == "anime_50")
        #expect(detail.score == "1.0")
        #expect(detail.kind == "tv")
    }

    @Test func userRatesListFromDocFixture() throws {
        let data = try fixtureData(named: "user_rates_list")
        let rates = try restDecoder.decode([UserRateV2].self, from: data)
        #expect(rates.count == 2)
        #expect(rates[0].id == 13)
        #expect(rates[0].status == "completed")
        #expect(rates[1].status == "planned")
    }

    @Test func whoamiFromDocFixture() throws {
        let data = try fixtureData(named: "whoami")
        let user = try restDecoder.decode(CurrentUser.self, from: data)
        #expect(user.id == 23_456_810)
        #expect(user.nickname == "Test")
        #expect(user.locale == "ru")
    }

    @Test func graphqlAnimesEnvelopeOk() throws {
        let data = try fixtureData(named: "graphql_animes_ok")
        let env = try gqlDecoder.decode(GraphQLAnimesEnvelope.self, from: data)
        #expect(env.errors == nil || env.errors?.isEmpty == true)
        #expect(env.data?.animes?.count == 1)
        #expect(env.data?.animes?.first?.id == 1)
        #expect(env.data?.animes?.first?.poster?.mainUrl?.contains("example.com") == true)
    }

    @Test func graphqlErrorsEnvelopeDecodes() throws {
        let data = try fixtureData(named: "graphql_errors")
        let env = try gqlDecoder.decode(GraphQLAnimesEnvelope.self, from: data)
        #expect(env.errors?.count == 1)
        #expect(env.errors?.first?.message.contains("bad") == true)
    }

    @Test func oauthTokenResponseDecodes() throws {
        let jsonString = """
        {"access_token":"tok","token_type":"Bearer","expires_in":3600,"refresh_token":"ref","created_at":1}
        """
        let json = Data(jsonString.utf8)
        let token = try JSONDecoder().decode(OAuthTokenResponse.self, from: json)
        #expect(token.accessToken == "tok")
        #expect(token.refreshToken == "ref")
        #expect(token.expiresIn == 3600)
    }
}

@Suite("Shikimori HTTP", .serialized)
struct ShikimoriHTTPTests {
    @Test func httpClientSendsUserAgentAndBearer() async throws {
        let config = ShikimoriConfiguration.testing(
            accessToken: "secret_token"
        )
        let session = MockURLSession.make()
        session.mshpMockHandler = { req in
            #expect(req.value(forHTTPHeaderField: "User-Agent") == config.userAgentAppName)
            #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer secret_token")
            let resp = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (resp, Data())
        }
        let throttler = RequestThrottler(minInterval: 0, maxRequestsInWindow: .max)
        let client = ShikimoriHTTPClient(configuration: config, session: session, throttler: throttler)
        let url = URL(string: "https://example.test/api/ping")!
        let req = URLRequest(url: url)
        _ = try await client.data(for: req)
        session.mshpMockHandler = nil
    }

    @Test func graphqlClientThrowsOnGraphQLErrors() async throws {
        let cfg = ShikimoriConfiguration.testing(
            apiBaseURL: URL(string: "https://api.test")!
        )
        let session = MockURLSession.make()
        let errBody = try fixtureData(named: "graphql_errors")
        session.mshpMockHandler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url?.path == "/api/graphql")
            let resp = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (resp, errBody)
        }
        let gql = ShikimoriGraphQLClient(configuration: cfg, session: session, throttler: unthrottled())
        await expectShikimoriError("graphqlErrors") {
            _ = try await gql.animes(search: "x", limit: 1)
        } matching: { error in
            guard case .graphqlErrors(let messages) = error else { return false }
            return messages.first?.message.contains("bad") == true
        }
        session.mshpMockHandler = nil
    }

    @Test func graphqlClientDecodesSuccessfulEnvelope() async throws {
        let session = MockURLSession.make()
        let okBody = try fixtureData(named: "graphql_animes_ok")
        session.mshpMockHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, okBody)
        }
        let gql = ShikimoriGraphQLClient(configuration: graphQLConfig(), session: session, throttler: unthrottled())
        let animes = try await gql.animes(ids: [1], limit: 1)
        #expect(animes.count == 1)
        #expect(animes.first?.id == 1)
        #expect(animes.first?.poster?.mainUrl?.contains("example.com") == true)
        session.mshpMockHandler = nil
    }

    @Test func graphqlClientDecodesIntrospectionEnvelope() async throws {
        let session = MockURLSession.make()
        let body = Data(#"{"data":{"__type":{"enumValues":[{"name":"tv"},{"name":"movie"}]}}}"#.utf8)
        session.mshpMockHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        let gql = ShikimoriGraphQLClient(configuration: graphQLConfig(), session: session, throttler: unthrottled())
        let values = try await gql.enumValues(typeName: "AnimeKindString")
        #expect(values == ["tv", "movie"])
        session.mshpMockHandler = nil
    }

    @Test func graphqlClientMapsMalformedBodyToDecodingError() async throws {
        let session = MockURLSession.make()
        session.mshpMockHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"data": {"animes": ["#.utf8))
        }
        let gql = ShikimoriGraphQLClient(configuration: graphQLConfig(), session: session, throttler: unthrottled())
        await expectShikimoriError("decoding") {
            _ = try await gql.animes(search: "x", limit: 1)
        } matching: { error in
            if case .decoding = error { return true }
            return false
        }
        session.mshpMockHandler = nil
    }

    @Test func graphqlClientMapsNon2xxToHTTPStatus() async throws {
        let session = MockURLSession.make()
        session.mshpMockHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 502, httpVersion: nil, headerFields: nil)!
            return (resp, Data("<html><h1>Сервер временно недоступен</h1></html>".utf8))
        }
        let gql = ShikimoriGraphQLClient(configuration: graphQLConfig(), session: session, throttler: unthrottled())
        // Goes through the raw-payload path (`animesByIdsDynamic` builds its
        // body by hand) — the status guard has to apply there too.
        await expectShikimoriError("httpStatus 502") {
            _ = try await gql.animesByIdsDynamic(ids: [1], search: nil, kindRaw: nil, ratingRaw: nil, season: nil)
        } matching: { error in
            guard case .httpStatus(let code, let body) = error else { return false }
            return code == 502 && body != nil
        }
        session.mshpMockHandler = nil
    }

    @Test func currentUserFallsBackToNextCandidateOnUnknownField() async throws {
        let key = ShikimoriGraphQLClient.currentUserQueryDefaultsKey
        let savedQuery = UserDefaults.standard.string(forKey: key)
        // The unit-test bundle runs inside the app, so this key is the real
        // app preference — put it back or a test run would pin the app to the
        // fallback query.
        defer {
            if let savedQuery {
                UserDefaults.standard.set(savedQuery, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.removeObject(forKey: key)

        let session = MockURLSession.make()
        let sent = SentBodies()
        let unknownField = Data(#"{"errors":[{"message":"Field 'avatarUrl' doesn't exist on type 'User'"}]}"#.utf8)
        let user = Data(#"{"data":{"currentUser":{"id":"42","nickname":"tester"}}}"#.utf8)
        session.mshpMockHandler = { req in
            let body = String(data: req.mshpInterceptedBody(), encoding: .utf8) ?? ""
            sent.append(body)
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, body.contains("avatarUrl") ? unknownField : user)
        }
        let gql = ShikimoriGraphQLClient(configuration: graphQLConfig(), session: session, throttler: unthrottled())
        let profile = try await gql.currentUser()
        #expect(profile.id == 42)
        #expect(profile.nickname == "tester")
        #expect(sent.all.count == 2)
        #expect(sent.all.first?.contains("avatarUrl") == true)
        #expect(sent.all.last?.contains("avatarUrl") == false)
        session.mshpMockHandler = nil
    }

    @Test func currentUserPropagatesNonFieldGraphQLError() async throws {
        let key = ShikimoriGraphQLClient.currentUserQueryDefaultsKey
        let savedQuery = UserDefaults.standard.string(forKey: key)
        defer {
            if let savedQuery {
                UserDefaults.standard.set(savedQuery, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.removeObject(forKey: key)

        let session = MockURLSession.make()
        let sent = SentBodies()
        let denied = Data(#"{"errors":[{"message":"Unauthorized"}]}"#.utf8)
        session.mshpMockHandler = { req in
            sent.append(String(data: req.mshpInterceptedBody(), encoding: .utf8) ?? "")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, denied)
        }
        let gql = ShikimoriGraphQLClient(configuration: graphQLConfig(), session: session, throttler: unthrottled())
        await expectShikimoriError("graphqlErrors") {
            _ = try await gql.currentUser()
        } matching: { error in
            guard case .graphqlErrors(let messages) = error else { return false }
            return messages.first?.message == "Unauthorized"
        }
        // A rejection that isn't about a missing field must stop the walk.
        #expect(sent.all.count == 1)
        session.mshpMockHandler = nil
    }

    @Test func oauthTokenPostsFormFields() async throws {
        let cfg = ShikimoriConfiguration.testing(
            clientId: "cid",
            clientSecret: "csec",
            redirectURI: "app://cb"
        )
        let session = MockURLSession.make()
        let tokenJsonString = """
        {"access_token":"a","token_type":"Bearer","expires_in":60,"refresh_token":"r"}
        """
        let tokenJson = Data(tokenJsonString.utf8)
        session.mshpMockHandler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url?.absoluteString.contains("oauth/token") == true)
            #expect(req.value(forHTTPHeaderField: "User-Agent") == cfg.userAgentAppName)
            let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
            #expect(body.contains("grant_type=authorization_code"))
            #expect(body.contains("client_id=cid"))
            #expect(body.contains("client_secret=csec"))
            #expect(body.contains("code=mycode"))
            #expect(body.contains("code_verifier=myverifier"))
            let resp = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (resp, tokenJson)
        }
        let oauth = OAuthTokenClient(configuration: cfg, session: session)
        let tok = try await oauth.exchangeAuthorizationCode("mycode", codeVerifier: "myverifier")
        #expect(tok.accessToken == "a")
        #expect(tok.refreshToken == "r")
        session.mshpMockHandler = nil
    }
}

@Suite("ShikimoriAPIError messages")
struct ShikimoriAPIErrorMessageTests {
    private static let shikimori502HTML = """
    <!DOCTYPE html>
    <html><head><meta charset="utf-8" /><title>502</title></head>
    <body>
    <div class="dialog">
    <p class="error-500">502</p>
    <h1>Сервер временно недоступен</h1>
    <p>Попробуй <a onclick='location.reload();'>перезагрузить страницу</a> или свяжись с <a href="mailto:mail@shikimori.org">администрацией сайта.</a></p>
    </div>
    </body></html>
    """

    @Test func htmlBodyCollapsesToTitle502() {
        let body = Data(Self.shikimori502HTML.utf8)
        let err = ShikimoriAPIError.httpStatus(code: 502, body: body)
        let message = err.errorDescription ?? ""

        // Localised reason wins, raw HTML is never surfaced, code is appended.
        #expect(message == "Сервер временно недоступен. (HTTP 502)")
        #expect(!message.contains("<"))
        #expect(!message.contains("DOCTYPE"))
        #expect(!message.contains("location.reload"))
    }

    @Test func plainTextBodyAppendedWhenInformative() {
        let body = Data("rate limit: 5 req/sec".utf8)
        let err = ShikimoriAPIError.httpStatus(code: 429, body: body)
        let message = err.errorDescription ?? ""

        #expect(message.hasPrefix("Слишком много запросов, попробуй позже."))
        #expect(message.contains("rate limit: 5 req/sec"))
        #expect(message.hasSuffix("(HTTP 429)"))
    }

    @Test func emptyBodyKeepsLocalisedTitleAndCode() {
        let err = ShikimoriAPIError.httpStatus(code: 503, body: nil)
        #expect(err.errorDescription == "Сервер на обслуживании. (HTTP 503)")
    }

    @Test func unknownStatusCodeFallsBackToBucket() {
        let err = ShikimoriAPIError.httpStatus(code: 418, body: nil)
        #expect(err.errorDescription == "Запрос отклонён сервером. (HTTP 418)")

        let serverErr = ShikimoriAPIError.httpStatus(code: 599, body: nil)
        #expect(serverErr.errorDescription == "Сервер вернул ошибку. (HTTP 599)")
    }

    @Test func longBodyIsClippedToOneLine() {
        let big = String(repeating: "lorem ipsum dolor sit amet ", count: 200)
        let body = Data(big.utf8)
        let err = ShikimoriAPIError.httpStatus(code: 500, body: body)
        let message = err.errorDescription ?? ""

        #expect(message.count < 350)
        #expect(!message.contains("\n"))
        #expect(message.contains("…"))
    }
}
