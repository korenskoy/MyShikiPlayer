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
