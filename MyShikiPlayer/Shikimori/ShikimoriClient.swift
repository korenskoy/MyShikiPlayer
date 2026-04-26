//
//  ShikimoriClient.swift
//  MyShikiPlayer
//

import Foundation

/// Facade over REST v1/v2, GraphQL, and OAuth token API.
final class ShikimoriClient: Sendable {
    let configuration: ShikimoriConfiguration
    private let session: URLSession
    let rest: ShikimoriRESTClient
    let graphql: ShikimoriGraphQLClient
    let oauth: OAuthTokenClient

    init(configuration: ShikimoriConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.rest = ShikimoriRESTClient(configuration: configuration, session: session)
        self.graphql = ShikimoriGraphQLClient(configuration: configuration, session: session)
        self.oauth = OAuthTokenClient(configuration: configuration, session: session)
    }

    func withAccessToken(_ token: String?) -> ShikimoriClient {
        ShikimoriClient(configuration: configuration.withAccessToken(token), session: session)
    }
}

extension ShikimoriConfiguration {
    func withAccessToken(_ token: String?) -> ShikimoriConfiguration {
        ShikimoriConfiguration(
            apiBaseURL: apiBaseURL,
            oauthBaseURL: oauthBaseURL,
            userAgentAppName: userAgentAppName,
            clientId: clientId,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            accessToken: token
        )
    }
}
