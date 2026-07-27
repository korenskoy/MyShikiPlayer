//
//  OAuthPKCE.swift
//  MyShikiPlayer
//

import CryptoKit
import Foundation
import Security

/// One-shot hardening material for a single browser sign-in: a CSRF `state`
/// plus a PKCE (RFC 7636) verifier/challenge pair.
///
/// The OAuth redirect is a custom URL scheme (`myshikiplayer://oauth`) that
/// any other app on the machine can register too, and the client secret ships
/// inside the DMG — so an intercepted authorization code must not be enough to
/// mint a token. `state` binds the callback to the run that started it;
/// `code_verifier` binds the code to this process.
struct OAuthPKCE: Sendable, Equatable {
    let state: String
    let codeVerifier: String

    /// `code_challenge_method` value sent alongside `codeChallenge`.
    static let challengeMethod = "S256"

    var codeChallenge: String {
        Self.challenge(for: codeVerifier)
    }

    static func generate() -> OAuthPKCE {
        // 32 random bytes → 43 base64url characters: exactly the RFC 7636
        // minimum verifier length, and every character is `unreserved`.
        OAuthPKCE(state: randomToken(byteCount: 32), codeVerifier: randomToken(byteCount: 32))
    }

    /// base64url(SHA256(verifier)) without padding — the `S256` transform.
    static func challenge(for verifier: String) -> String {
        base64URLEncoded(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func randomToken(byteCount: Int) -> String {
        base64URLEncoded(randomBytes(byteCount))
    }

    static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess {
            return Data(bytes)
        }
        // SecRandomCopyBytes only fails when the system entropy source is
        // unavailable. Swift's default RNG is CSPRNG-backed on Apple
        // platforms, so this is a fallback rather than a downgrade.
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) })
    }
}
