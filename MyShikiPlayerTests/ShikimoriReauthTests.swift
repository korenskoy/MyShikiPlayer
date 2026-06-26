//
//  ShikimoriReauthTests.swift
//  MyShikiPlayerTests
//
//  Locks the live-401 policy: a rejected token must ask for re-auth, while a
//  transient failure (network blip, banned host, 5xx) must leave the session
//  untouched. See `feedback_player_resilience`.
//

import Foundation
import Testing
@testable import MyShikiPlayer

@Suite("Shikimori live-401 refresh classification")
struct ShikimoriReauthTests {
    @Test func http401MeansReauth() {
        #expect(ShikimoriAuthController.classifyRefreshError(
            ShikimoriAPIError.httpStatus(code: 401, body: nil)
        ) == .authRejected)
    }

    @Test func http403MeansReauth() {
        #expect(ShikimoriAuthController.classifyRefreshError(
            ShikimoriAPIError.httpStatus(code: 403, body: nil)
        ) == .authRejected)
    }

    @Test func http500IsTransient() {
        #expect(ShikimoriAuthController.classifyRefreshError(
            ShikimoriAPIError.httpStatus(code: 500, body: nil)
        ) == .transient)
    }

    @Test func networkErrorIsTransient() {
        #expect(ShikimoriAuthController.classifyRefreshError(
            URLError(.notConnectedToInternet)
        ) == .transient)
    }
}

@Suite("OAuth redirect credential policy")
struct OAuthRedirectPolicyTests {
    private func url(_ string: String) -> URL { URL(string: string)! }

    @Test func allowsShikimoriMirror() {
        // The real-world case: .one 301s to .io — both trusted mirrors.
        #expect(OAuthRedirectPolicy.mayForwardCredentials(
            from: url("https://shikimori.one/oauth/token"),
            to: url("https://shikimori.io/oauth/token")))
    }

    @Test func allowsSameHost() {
        #expect(OAuthRedirectPolicy.mayForwardCredentials(
            from: url("https://shikimori.io/oauth/token"),
            to: url("https://shikimori.io/oauth/token?x=1")))
    }

    @Test func allowsShikimoriSubdomain() {
        #expect(OAuthRedirectPolicy.mayForwardCredentials(
            from: url("https://shikimori.one/x"),
            to: url("https://www.shikimori.io/oauth/token")))
    }

    @Test func rejectsForeignHost() {
        #expect(!OAuthRedirectPolicy.mayForwardCredentials(
            from: url("https://shikimori.one/x"),
            to: url("https://evil.com/oauth/token")))
    }

    @Test func rejectsLookalikeHost() {
        // evilshikimori.io must NOT match the shikimori.io mirror suffix.
        #expect(!OAuthRedirectPolicy.mayForwardCredentials(
            from: url("https://shikimori.one/x"),
            to: url("https://evilshikimori.io/oauth/token")))
    }

    @Test func rejectsHttpDowngrade() {
        #expect(!OAuthRedirectPolicy.mayForwardCredentials(
            from: url("https://shikimori.one/x"),
            to: url("http://shikimori.io/oauth/token")))
    }
}

@Suite("Trusted OAuth hosts store")
struct TrustedOAuthHostsStoreTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.trustedHosts.\(UUID().uuidString)")!
    }

    @Test func addThenContainsCaseInsensitive() {
        let defaults = freshDefaults()
        #expect(!TrustedOAuthHostsStore.contains("new.example.com", defaults))
        TrustedOAuthHostsStore.add("New.Example.COM", defaults)
        #expect(TrustedOAuthHostsStore.contains("new.example.com", defaults))
    }
}
