//
//  OAuthSecurityTests.swift
//  MyShikiPlayerTests
//
//  Locks the hardening around the browser sign-in: PKCE material, the `state`
//  check on the custom-scheme callback, and the URL allowlists that decide
//  what may be opened or treated as a Shikimori host.
//

import Foundation
import Testing
@testable import MyShikiPlayer

@Suite("OAuth PKCE material")
struct OAuthPKCETests {
    /// RFC 7636 Appendix B reference vector.
    @Test func challengeMatchesRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(OAuthPKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatedVerifierMatchesItsOwnChallenge() {
        let pkce = OAuthPKCE.generate()
        #expect(pkce.codeChallenge == OAuthPKCE.challenge(for: pkce.codeVerifier))
    }

    @Test func generatedMaterialIsUnreservedAndLongEnough() {
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        )
        let pkce = OAuthPKCE.generate()
        // RFC 7636 §4.1: 43…128 characters from the unreserved set.
        #expect(pkce.codeVerifier.count >= 43)
        #expect(pkce.codeVerifier.count <= 128)
        #expect(pkce.codeVerifier.unicodeScalars.allSatisfy { unreserved.contains($0) })
        #expect(pkce.state.count >= 43)
        #expect(pkce.state.unicodeScalars.allSatisfy { unreserved.contains($0) })
    }

    @Test func everyRunGetsFreshMaterial() {
        let first = OAuthPKCE.generate()
        let second = OAuthPKCE.generate()
        #expect(first.state != second.state)
        #expect(first.codeVerifier != second.codeVerifier)
        #expect(first.state != first.codeVerifier)
    }

    @Test func authorizeURLCarriesStateAndChallenge() throws {
        let pkce = OAuthPKCE.generate()
        let url = try ShikimoriOAuthBrowserLogin.buildAuthorizeURL(
            configuration: .testing(),
            scopes: ["user_rates"],
            pkce: pkce
        )
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(value("state") == pkce.state)
        #expect(value("code_challenge") == pkce.codeChallenge)
        #expect(value("code_challenge_method") == "S256")
        #expect(value("response_type") == "code")
        // The verifier itself must never leave the process over the front channel.
        #expect(value("code_verifier") == nil)
    }

    @Test func maskedLogStringHidesStateAndChallenge() throws {
        let pkce = OAuthPKCE.generate()
        let url = try ShikimoriOAuthBrowserLogin.buildAuthorizeURL(
            configuration: .testing(),
            scopes: ["user_rates"],
            pkce: pkce
        )
        let masked = ShikimoriOAuthBrowserLogin.maskedOAuthURLString(url)
        #expect(!masked.contains(pkce.state))
        #expect(!masked.contains(pkce.codeChallenge))
    }
}

@Suite("OAuth callback state validation")
struct OAuthCallbackValidationTests {
    private let expected = "expected-state-value"

    private func callback(_ query: String) -> URL {
        URL(string: "myshikiplayer://oauth?\(query)")!
    }

    @Test func acceptsMatchingState() {
        let result = ShikimoriOAuthBrowserLogin.evaluateCallback(
            url: callback("code=abc&state=\(expected)"),
            expectedState: expected
        )
        #expect(result == .code("abc"))
    }

    @Test func rejectsForeignState() {
        // A hostile app registered on myshikiplayer:// injecting its own code.
        let result = ShikimoriOAuthBrowserLogin.evaluateCallback(
            url: callback("code=attacker-code&state=someone-else"),
            expectedState: expected
        )
        #expect(result == .stateMismatch)
    }

    @Test func rejectsMissingState() {
        let result = ShikimoriOAuthBrowserLogin.evaluateCallback(
            url: callback("code=attacker-code"),
            expectedState: expected
        )
        #expect(result == .stateMismatch)
    }

    @Test func rejectsCallbackWithoutPendingRun() {
        let result = ShikimoriOAuthBrowserLogin.evaluateCallback(
            url: callback("code=abc&state=\(expected)"),
            expectedState: nil
        )
        #expect(result == .stateMismatch)
    }

    @Test func reportsMissingCodeOnlyAfterStatePasses() {
        let result = ShikimoriOAuthBrowserLogin.evaluateCallback(
            url: callback("state=\(expected)"),
            expectedState: expected
        )
        #expect(result == .missingCode)
    }

    @Test func emptyCodeCountsAsMissing() {
        let result = ShikimoriOAuthBrowserLogin.evaluateCallback(
            url: callback("code=&state=\(expected)"),
            expectedState: expected
        )
        #expect(result == .missingCode)
    }

    @Test func surfacesServerErrorDescription() {
        let result = ShikimoriOAuthBrowserLogin.evaluateCallback(
            url: callback("error=access_denied&error_description=Denied&state=\(expected)"),
            expectedState: expected
        )
        #expect(result == .failure("Denied"))
    }

    @Test func forgedErrorWithoutStateIsRejected() {
        // An error injected by a third party must not surface as a Shikimori
        // message — it is an unrecognised callback like any other.
        let result = ShikimoriOAuthBrowserLogin.evaluateCallback(
            url: callback("error=access_denied&error_description=Denied"),
            expectedState: expected
        )
        #expect(result == .stateMismatch)
    }
}

@Suite("External URL allowlist")
struct ShikimoriExternalURLTests {
    private func isSafe(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return ShikimoriText.isSafeExternalURL(url)
    }

    @Test func allowsWebAndMailSchemes() {
        #expect(isSafe("https://shikimori.one/animes/1"))
        #expect(isSafe("http://example.com"))
        #expect(isSafe("mailto:mail@shikimori.org"))
        #expect(isSafe("HTTPS://EXAMPLE.COM"))
    }

    @Test func rejectsLocalAndScriptSchemes() {
        #expect(!isSafe("file:///etc/passwd"))
        #expect(!isSafe("javascript:alert(1)"))
        #expect(!isSafe("myshikiplayer://oauth"))
        #expect(!isSafe("ftp://example.com/x"))
    }

    @Test func rejectsSchemelessInput() {
        #expect(!isSafe("shikimori.one/animes/1"))
        #expect(!isSafe("/system/user_images/1.jpg"))
    }
}

@Suite("Shikimori hosts store")
struct ShikimoriHostsStoreTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.shikimoriHosts.\(UUID().uuidString)")!
    }

    @Test func emptyOrMissingOverrideIsNil() {
        #expect(ShikimoriHostsStore.overrideURL(raw: nil) == nil)
        #expect(ShikimoriHostsStore.overrideURL(raw: "") == nil)
        #expect(ShikimoriHostsStore.overrideURL(raw: "   ") == nil)
    }

    @Test func bareHostBecomesHTTPSURL() {
        #expect(ShikimoriHostsStore.overrideURL(raw: "shikimori.me")?.absoluteString == "https://shikimori.me")
    }

    @Test func fullURLKeepsOnlyTheHost() {
        #expect(ShikimoriHostsStore.overrideURL(
            raw: "http://shikimori.one/animes/1?x=2"
        )?.absoluteString == "https://shikimori.one")
    }

    @Test func garbageInputIsRejected() {
        #expect(ShikimoriHostsStore.overrideURL(raw: "shi kimori.me") == nil)
        #expect(ShikimoriHostsStore.overrideURL(raw: "shikimori") == nil)
        #expect(ShikimoriHostsStore.overrideURL(raw: "шикимори.рф") == nil)
        #expect(ShikimoriHostsStore.overrideURL(raw: "host/../etc") == nil)
    }

    @Test func hostLikeValidation() {
        #expect(ShikimoriHostsStore.isValidHostLike("shikimori.me"))
        #expect(ShikimoriHostsStore.isValidHostLike("shikimori.me:3000"))
        #expect(!ShikimoriHostsStore.isValidHostLike(""))
        #expect(!ShikimoriHostsStore.isValidHostLike("nodot"))
        #expect(!ShikimoriHostsStore.isValidHostLike("has space.com"))
    }

    @Test func acceptableInputAllowsEmptyMeaningDefault() {
        #expect(ShikimoriHostsStore.isAcceptableInput(""))
        #expect(ShikimoriHostsStore.isAcceptableInput("shikimori.io"))
        #expect(!ShikimoriHostsStore.isAcceptableInput("!!!"))
    }

    @Test func knownHostCoversEveryMirrorAndSubdomains() {
        let defaults = freshDefaults()
        for mirror in ShikimoriHostsStore.knownMirrors {
            #expect(ShikimoriHostsStore.isKnownHost(mirror, defaults: defaults))
        }
        #expect(ShikimoriHostsStore.isKnownHost("Shikimori.ONE", defaults: defaults))
        #expect(ShikimoriHostsStore.isKnownHost("desu.shikimori.io", defaults: defaults))
        #expect(!ShikimoriHostsStore.isKnownHost("evilshikimori.io", defaults: defaults))
        #expect(!ShikimoriHostsStore.isKnownHost(nil, defaults: defaults))
    }

    @Test func knownHostFollowsUserOverride() {
        let defaults = freshDefaults()
        #expect(!ShikimoriHostsStore.isKnownHost("shiki.example.com", defaults: defaults))
        defaults.set("shiki.example.com", forKey: ShikimoriHostsStore.Field.api.defaultsKey)
        #expect(ShikimoriHostsStore.isKnownHost("shiki.example.com", defaults: defaults))
    }

    @Test func imageDetectionUsesKnownHosts() {
        // No image extension: only a Shikimori `/system/` upload qualifies.
        #expect(ShikimoriText.isImageURL(URL(string: "https://shikimori.one/system/user_images/1")!))
        #expect(!ShikimoriText.isImageURL(URL(string: "https://example.com/system/user_images/1")!))
        #expect(ShikimoriText.isImageURL(URL(string: "https://example.com/pic.png")!))
    }
}
