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
        MockURLProtocol.handler = { req in
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
        let client = ShikimoriHTTPClient(configuration: config, session: session, minRequestInterval: 0)
        let url = URL(string: "https://example.test/api/ping")!
        let req = URLRequest(url: url)
        _ = try await client.data(for: req)
        MockURLProtocol.handler = nil
    }

    @Test func graphqlClientThrowsOnGraphQLErrors() async throws {
        let cfg = ShikimoriConfiguration.testing(
            apiBaseURL: URL(string: "https://api.test")!
        )
        let session = MockURLSession.make()
        let errBody = try fixtureData(named: "graphql_errors")
        MockURLProtocol.handler = { req in
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
        let gql = ShikimoriGraphQLClient(configuration: cfg, session: session)
        await #expect(throws: ShikimoriAPIError.self) {
            try await gql.animes(search: "x", limit: 1)
        }
        MockURLProtocol.handler = nil
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
        MockURLProtocol.handler = { req in
            #expect(req.httpMethod == "POST")
            #expect(req.url?.absoluteString.contains("oauth/token") == true)
            #expect(req.value(forHTTPHeaderField: "User-Agent") == cfg.userAgentAppName)
            let body = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
            #expect(body.contains("grant_type=authorization_code"))
            #expect(body.contains("client_id=cid"))
            #expect(body.contains("client_secret=csec"))
            #expect(body.contains("code=mycode"))
            let resp = HTTPURLResponse(
                url: req.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (resp, tokenJson)
        }
        let oauth = OAuthTokenClient(configuration: cfg, session: session)
        let tok = try await oauth.exchangeAuthorizationCode("mycode")
        #expect(tok.accessToken == "a")
        #expect(tok.refreshToken == "r")
        MockURLProtocol.handler = nil
    }
}
