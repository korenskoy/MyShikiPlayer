//
//  NetworkLogMaskingTests.swift
//  MyShikiPlayerTests
//

import Foundation
import Testing
@testable import MyShikiPlayer

/// Turns the diagnostics toggle on for the duration of a test and puts the
/// previous value back. Unit tests run inside the host app, so this key is the
/// user's real preference — leaking it on would start filling the ring buffer.
private func withNetworkLogsEnabled(_ body: () throws -> Void) rethrows {
    let key = "settings.networkLogsEnabled"
    let previous = UserDefaults.standard.object(forKey: key)
    defer {
        if let previous {
            UserDefaults.standard.set(previous, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    UserDefaults.standard.set(true, forKey: key)
    try body()
}

private func queryPairs(of masked: String) -> [String: String] {
    guard let components = URLComponents(string: masked), let items = components.queryItems else { return [:] }
    return items.reduce(into: [:]) { $0[$1.name] = $1.value ?? "" }
}

@Suite("NetworkLogStore.maskedURLString")
struct NetworkLogMaskedURLTests {
    private func mask(_ string: String) -> String {
        NetworkLogStore.maskedURLString(URL(string: string)!)
    }

    @Test func sensitiveQueryItemsAreReplaced() {
        let masked = mask("https://shikimori.one/oauth/token?code=abc&client_secret=s3cr3t&refresh_token=r&access_token=a&token=t")
        let pairs = queryPairs(of: masked)
        #expect(pairs["code"] == "***")
        #expect(pairs["client_secret"] == "***")
        #expect(pairs["refresh_token"] == "***")
        #expect(pairs["access_token"] == "***")
        #expect(pairs["token"] == "***")
        // No original secret survives anywhere in the string.
        #expect(!masked.contains("abc"))
        #expect(!masked.contains("s3cr3t"))
    }

    @Test func nonSensitiveQueryItemsSurviveUntouched() {
        let masked = mask("https://shikimori.one/api/animes?page=2&limit=50&search=naruto&code=abc")
        let pairs = queryPairs(of: masked)
        #expect(pairs["page"] == "2")
        #expect(pairs["limit"] == "50")
        #expect(pairs["search"] == "naruto")
        #expect(pairs["code"] == "***")
    }

    @Test func parameterNameMatchingIsCaseInsensitive() {
        // The lookup lowercases the item name, so shouty variants mask too.
        let masked = mask("https://shikimori.one/oauth/token?CODE=abc&Client_Secret=xyz&TOKEN=t")
        let pairs = queryPairs(of: masked)
        #expect(pairs["CODE"] == "***")
        #expect(pairs["Client_Secret"] == "***")
        #expect(pairs["TOKEN"] == "***")
    }

    @Test func urlWithoutQueryIsReturnedUnchanged() {
        #expect(mask("https://shikimori.one/api/users/whoami") == "https://shikimori.one/api/users/whoami")
        #expect(mask("https://shikimori.one") == "https://shikimori.one")
    }

    @Test func valuelessSensitiveParameterStillMasks() {
        // `?code` with no `=` — the item exists with a nil value.
        #expect(queryPairs(of: mask("https://shikimori.one/cb?code"))["code"] == "***")
    }

    @Test func nonHTTPSchemeSurvivesIntact() {
        // No query component to rewrite — the URL must come back untouched
        // rather than through the `absoluteString` fallback losing anything.
        #expect(NetworkLogStore.maskedURLString(URL(string: "mailto:mail@shikimori.org")!) == "mailto:mail@shikimori.org")
    }

    @Test func fragmentAndPathAreKeptWhileSecretIsMasked() {
        let masked = mask("https://shikimori.one/oauth/authorize?client_id=pub&code=secret#frag")
        #expect(masked.contains("/oauth/authorize"))
        #expect(masked.contains("client_id=pub"))
        #expect(masked.contains("code=***"))
        #expect(masked.contains("#frag"))
        #expect(!masked.contains("code=secret"))
    }
}

@Suite("NetworkLogStore.sanitizeJSONObject")
struct NetworkLogSanitizeTests {
    private func sanitizedDictionary(_ json: String) throws -> [String: Any] {
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try #require(NetworkLogStore.sanitizeJSONObject(parsed) as? [String: Any])
    }

    @Test func topLevelSensitiveKeysAreMasked() throws {
        let out = try sanitizedDictionary(
            #"{"access_token":"AAA","refresh_token":"RRR","client_secret":"CCC","token":"TTT","code":"XXX","keep":"me"}"#
        )
        #expect(out["access_token"] as? String == "***")
        #expect(out["refresh_token"] as? String == "***")
        #expect(out["client_secret"] as? String == "***")
        #expect(out["token"] as? String == "***")
        #expect(out["code"] as? String == "***")
        #expect(out["keep"] as? String == "me")
    }

    @Test func keyMatchingIsCaseInsensitive() throws {
        let out = try sanitizedDictionary(#"{"Access_Token":"AAA","REFRESH_TOKEN":"RRR"}"#)
        #expect(out["Access_Token"] as? String == "***")
        #expect(out["REFRESH_TOKEN"] as? String == "***")
    }

    @Test func nestedObjectsAreMaskedRecursively() throws {
        let out = try sanitizedDictionary(#"{"outer":{"inner":{"token":"SECRET","id":7}}}"#)
        let outer = try #require(out["outer"] as? [String: Any])
        let inner = try #require(outer["inner"] as? [String: Any])
        #expect(inner["token"] as? String == "***")
        #expect(inner["id"] as? Int == 7)
    }

    @Test func objectsInsideArraysAreMaskedRecursively() throws {
        // The array branch maps each element back through the sanitizer, so a
        // secret buried in a list is masked as well.
        let out = try sanitizedDictionary(#"{"items":[{"access_token":"SECRET","keep":"ok"},{"plain":"value"}]}"#)
        let items = try #require(out["items"] as? [Any])
        #expect(items.count == 2)
        let first = try #require(items[0] as? [String: Any])
        #expect(first["access_token"] as? String == "***")
        #expect(first["keep"] as? String == "ok")
        // Elements are plain values, not `Optional<Any>` boxes.
        #expect(items[0] is [String: Any])
    }

    @Test func sanitizedTreeStaysSerializable() throws {
        // `previewFromResponseData` re-encodes the sanitized tree right after
        // masking, so anything the array branch produces has to stay valid
        // input for JSONSerialization.
        let out = try sanitizedDictionary(#"{"items":[{"token":"SECRET"},"plain",3],"nested":{"code":"C"}}"#)
        #expect(JSONSerialization.isValidJSONObject(out))
        let data = try JSONSerialization.data(withJSONObject: out)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("SECRET"))
        #expect(text.contains("***"))
        #expect(text.contains("plain"))
    }

    @Test func topLevelArrayIsSanitized() throws {
        let parsed = try JSONSerialization.jsonObject(with: Data(#"[{"token":"SECRET"},{"id":1}]"#.utf8))
        let array = try #require(NetworkLogStore.sanitizeJSONObject(parsed) as? [Any])
        let first = try #require(array[0] as? [String: Any])
        #expect(first["token"] as? String == "***")
    }

    @Test func scalarsAndNullPassThrough() throws {
        #expect(NetworkLogStore.sanitizeJSONObject("plain") as? String == "plain")
        #expect(NetworkLogStore.sanitizeJSONObject(42) as? Int == 42)
        let parsed = try JSONSerialization.jsonObject(with: Data(#"{"a":null}"#.utf8))
        let out = try #require(NetworkLogStore.sanitizeJSONObject(parsed) as? [String: Any])
        #expect(out["a"] is NSNull)
    }
}

@Suite("NetworkLogStore.previewFromResponseData", .serialized)
struct NetworkLogPreviewTests {
    @Test func realOAuthTokenBodyLeaksNoSecrets() throws {
        let body = #"{"access_token":"AAA111","token_type":"Bearer","expires_in":3600,"refresh_token":"RRR222"}"#
        try withNetworkLogsEnabled {
            let preview = NetworkLogStore.previewFromResponseData(Data(body.utf8), maxBytes: 1024)
            #expect(!preview.contains("AAA111"))
            #expect(!preview.contains("RRR222"))
            #expect(preview.contains("***"))
            // Non-sensitive fields stay readable so the log is still useful.
            #expect(preview.contains("Bearer"))
            #expect(preview.contains("expires_in"))
        }
    }

    @Test func nestedSecretsInResponseBodyAreMasked() throws {
        let body = #"{"data":{"sessions":[{"access_token":"LEAK","device":"mac"}]}}"#
        try withNetworkLogsEnabled {
            let preview = NetworkLogStore.previewFromResponseData(Data(body.utf8), maxBytes: 1024)
            #expect(!preview.contains("LEAK"))
            #expect(preview.contains("***"))
            #expect(preview.contains("mac"))
        }
    }

    @Test func disabledLoggingSkipsWorkAndReturnsEmpty() {
        let key = "settings.networkLogsEnabled"
        let previous = UserDefaults.standard.object(forKey: key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.set(false, forKey: key)
        #expect(NetworkLogStore.previewFromResponseData(Data(#"{"access_token":"A"}"#.utf8), maxBytes: 1024).isEmpty)
    }

    @Test func nonJSONBodyIsQuotedAndNewlinesCollapsed() throws {
        try withNetworkLogsEnabled {
            let preview = NetworkLogStore.previewFromResponseData(Data("line1\nline2".utf8), maxBytes: 1024)
            #expect(!preview.contains("\n"))
            #expect(preview.contains("line1 line2"))
        }
    }

    @Test func emptyBodyRendersAsEmptyQuotes() throws {
        try withNetworkLogsEnabled {
            #expect(NetworkLogStore.previewFromResponseData(Data(), maxBytes: 1024) == "\"\"")
        }
    }

    @Test func oversizedNonJSONBodyIsTruncated() throws {
        let body = String(repeating: "a", count: 500)
        try withNetworkLogsEnabled {
            let preview = NetworkLogStore.previewFromResponseData(Data(body.utf8), maxBytes: 64)
            #expect(preview.contains("…"))
            #expect(preview.count < 100)
        }
    }
}
