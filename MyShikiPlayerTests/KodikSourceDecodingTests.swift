//
//  KodikSourceDecodingTests.swift
//  MyShikiPlayerTests
//

import Foundation
import Testing
@testable import MyShikiPlayer

/// Fixtures are the encoded forms of two plaintext links. Each was produced by
/// base64-encoding the plaintext and then, for the ROT variants, rotating the
/// letters by 8 — the inverse of the resolver's ROT18, since 18 + 8 == 26.
private enum Fixture {
    /// Base64 of this one contains neither `+`, `/` nor padding, so it
    /// exercises the plain strategies without tripping the URL heuristic.
    static let plainA = "//cdn.example.com/hls/master.m3u8"
    static let base64A = "Ly9jZG4uZXhhbXBsZS5jb20vaGxzL21hc3Rlci5tM3U4"
    static let rot8Base64A = "Tg9rHO4cHFppjFJaHA5rj20diOfhT21pk3Ztkq5bU3C4"

    /// Base64 of this one needs `=` padding, so stripping the padding (as
    /// URL-safe encoders do) is what forces the `_urlsafe` strategies.
    static let plainB = "//test.example.com/stream/master.m3u8"
    static let base64UnpaddedB = "Ly90ZXN0LmV4YW1wbGUuY29tL3N0cmVhbS9tYXN0ZXIubTN1OA"
    static let rot8Base64UnpaddedB = "Tg90HFV0TuD4GE1ejOCcG29bT3V0kuDpjA9bGFV0HFQcjBV1WI"

    /// Base64 with a `-`/`_` substitution (the query `?` at the end encodes to
    /// a `/` in the standard alphabet).
    static let plainC = "//cdn.example.com/hls/master.m3u8?t=aa?"
    static let urlsafeC = "Ly9jZG4uZXhhbXBsZS5jb20vaGxzL21hc3Rlci5tM3U4P3Q9YWE_"
    static let standardC = "Ly9jZG4uZXhhbXBsZS5jb20vaGxzL21hc3Rlci5tM3U4P3Q9YWE/"
}

private func makeResolver() -> KodikVideoLinksResolver {
    // Explicit configuration so the test never depends on user host overrides.
    KodikVideoLinksResolver(configuration: .default)
}

@Suite("Kodik decodeSourceURL strategies")
struct KodikDecodeSourceURLTests {
    private var resolver: KodikVideoLinksResolver { makeResolver() }

    @Test func directLinkIsUsedAsIs() {
        let decoded = resolver.decodeSourceURL(from: Fixture.plainA)
        #expect(decoded?.strategy == "direct")
        #expect(decoded?.urlString == "https://cdn.example.com/hls/master.m3u8")
    }

    @Test func standardBase64IsDecoded() {
        let decoded = resolver.decodeSourceURL(from: Fixture.base64A)
        #expect(decoded?.strategy == "base64")
        #expect(decoded?.urlString == "https://cdn.example.com/hls/master.m3u8")
    }

    @Test func unpaddedBase64GoesThroughTheURLSafeStrategy() {
        // Padding is what standard `Data(base64Encoded:)` chokes on, so the
        // first strategy fails and `normalizeBase64` re-pads for the second.
        let decoded = resolver.decodeSourceURL(from: Fixture.base64UnpaddedB)
        #expect(decoded?.strategy == "base64_urlsafe")
        #expect(decoded?.urlString == "https://test.example.com/stream/master.m3u8")
    }

    @Test func urlSafeAlphabetGoesThroughTheURLSafeStrategy() {
        let decoded = resolver.decodeSourceURL(from: Fixture.urlsafeC)
        #expect(decoded?.strategy == "base64_urlsafe")
        #expect(decoded?.urlString == "https://cdn.example.com/hls/master.m3u8?t=aa?")
    }

    @Test func rotatedBase64IsUnrotatedThenDecoded() {
        let decoded = resolver.decodeSourceURL(from: Fixture.rot8Base64A)
        #expect(decoded?.strategy == "rot18_base64")
        #expect(decoded?.urlString == "https://cdn.example.com/hls/master.m3u8")
    }

    @Test func rotatedUnpaddedBase64UsesTheLastStrategy() {
        let decoded = resolver.decodeSourceURL(from: Fixture.rot8Base64UnpaddedB)
        #expect(decoded?.strategy == "rot18_base64_urlsafe")
        #expect(decoded?.urlString == "https://test.example.com/stream/master.m3u8")
    }

    @Test func absoluteHTTPLinkIsPreserved() {
        let decoded = resolver.decodeSourceURL(from: "https://cdn.example.com/a.mp4")
        #expect(decoded?.strategy == "direct")
        #expect(decoded?.urlString == "https://cdn.example.com/a.mp4")
    }

    @Test func garbageInputReturnsNil() {
        #expect(resolver.decodeSourceURL(from: "") == nil)
        #expect(resolver.decodeSourceURL(from: "   ") == nil)
        #expect(resolver.decodeSourceURL(from: "garbage") == nil)
        #expect(resolver.decodeSourceURL(from: "!!!!") == nil)
        // Valid base64 that decodes to something which is not a URL.
        #expect(resolver.decodeSourceURL(from: "ZZZZ") == nil)
        #expect(resolver.decodeSourceURL(from: "тест") == nil)
    }

    /// Regression: standard base64 contains `/`, and the direct-URL heuristic
    /// used to claim any string with a slash — so roughly half of all payloads
    /// came back as `https://<base64>` and never played.
    @Test func standardBase64ContainingSlashIsDecodedNotTreatedAsALink() {
        let decoded = resolver.decodeSourceURL(from: Fixture.standardC)
        #expect(decoded?.strategy == "base64")
        #expect(decoded?.urlString == "https://cdn.example.com/hls/master.m3u8?t=aa?")
        #expect(decoded?.urlString.contains(Fixture.standardC) == false)
        // The URL-safe form of the very same payload lands on its own strategy.
        let urlSafe = resolver.decodeSourceURL(from: Fixture.urlsafeC)
        #expect(urlSafe?.strategy == "base64_urlsafe")
        #expect(urlSafe?.urlString == "https://cdn.example.com/hls/master.m3u8?t=aa?")
    }

    /// A dot cannot appear in either base64 alphabet, so a dotted first
    /// segment is the signal that separates a bare link from a payload.
    @Test func bareHostWithDotIsStillTreatedAsADirectLink() {
        // No media extension here, so this rides on the host rule alone.
        let decoded = resolver.decodeSourceURL(from: "cdn.example.com/hls/stream")
        #expect(decoded?.strategy == "direct")
        #expect(decoded?.urlString == "https://cdn.example.com/hls/stream")
        #expect(resolver.decodeSourceURL(from: "cdn.example.com/hls/master.m3u8")?.strategy == "direct")
    }
}

@Suite("Kodik normalizeDirectURL")
struct KodikNormalizeDirectURLTests {
    private var resolver: KodikVideoLinksResolver { makeResolver() }

    @Test func protocolRelativeLinkGetsHTTPS() {
        #expect(resolver.normalizeDirectURL("//host/x") == "https://host/x")
    }

    @Test func absoluteLinksAreLeftAlone() {
        #expect(resolver.normalizeDirectURL("https://host/x") == "https://host/x")
        #expect(resolver.normalizeDirectURL("http://host/x") == "http://host/x")
    }

    @Test func mediaExtensionImpliesAHost() {
        #expect(resolver.normalizeDirectURL("host.m3u8") == "https://host.m3u8")
        #expect(resolver.normalizeDirectURL("host.mp4") == "https://host.mp4")
    }

    @Test func dottedFirstSegmentImpliesAHost() {
        #expect(resolver.normalizeDirectURL("cdn.example.com/path") == "https://cdn.example.com/path")
        #expect(resolver.normalizeDirectURL("cdn.example.com:8080/x") == "https://cdn.example.com:8080/x")
    }

    @Test func whitespaceIsTrimmedBeforeMatching() {
        #expect(resolver.normalizeDirectURL("  //host/x  ") == "https://host/x")
        #expect(resolver.normalizeDirectURL("\n https://host/x \t") == "https://host/x")
    }

    @Test func slashAloneNoLongerImpliesAHost() {
        // A dotless first segment is not a host: without this, any standard
        // base64 payload (the alphabet contains `/`) was taken for a link.
        #expect(resolver.normalizeDirectURL("host/path") == nil)
        #expect(resolver.normalizeDirectURL("abc/def") == nil)
    }

    @Test func pathOnlyInputIsRejectedInsteadOfBecomingAHostlessURL() {
        // Used to produce "https:///path/only" — a URL with an empty host.
        #expect(resolver.normalizeDirectURL("/path/only") == nil)
        #expect(resolver.normalizeDirectURL("/") == nil)
    }

    @Test func inputWithoutSlashOrMediaExtensionIsRejected() {
        #expect(resolver.normalizeDirectURL("garbage") == nil)
        #expect(resolver.normalizeDirectURL("") == nil)
        #expect(resolver.normalizeDirectURL("   ") == nil)
        // A dotted host with no path is still not a media link — unchanged.
        #expect(resolver.normalizeDirectURL("host.example.com") == nil)
    }
}

@Suite("Kodik normalizeBase64")
struct KodikNormalizeBase64Tests {
    private var resolver: KodikVideoLinksResolver { makeResolver() }

    @Test func urlSafeCharactersAreMappedBack() {
        #expect(resolver.normalizeBase64("a-b_c") == "a+b/c===")
    }

    @Test func paddingIsToppedUpToAMultipleOfFour() {
        #expect(resolver.normalizeBase64("abcd") == "abcd")
        #expect(resolver.normalizeBase64("abc") == "abc=")
        #expect(resolver.normalizeBase64("ab") == "ab==")
        #expect(resolver.normalizeBase64("a") == "a===")
    }

    @Test func emptyStringNeedsNoPadding() {
        #expect(resolver.normalizeBase64("") == "")
    }
}

@Suite("Kodik rotateLettersBy18")
struct KodikRotateLettersTests {
    private var resolver: KodikVideoLinksResolver { makeResolver() }

    @Test func lettersShiftByEighteenInBothCases() {
        #expect(resolver.rotateLettersBy18("A") == "S")
        #expect(resolver.rotateLettersBy18("a") == "s")
        // Wraps around the end of the alphabet: z (25) + 18 == 43 % 26 == 17 -> r.
        #expect(resolver.rotateLettersBy18("z") == "r")
        #expect(resolver.rotateLettersBy18("Z") == "R")
    }

    @Test func digitsAndSymbolsAreUntouched() {
        #expect(resolver.rotateLettersBy18("0123456789") == "0123456789")
        #expect(resolver.rotateLettersBy18("+/=-_") == "+/=-_")
        #expect(resolver.rotateLettersBy18("тест") == "тест")
    }

    @Test func rotatingByEighteenTwiceIsNotIdentity() {
        // 18 + 18 == 36 % 26 == 10, so the transform is not an involution —
        // encoded payloads must be pre-rotated by 8, not by 18.
        #expect(resolver.rotateLettersBy18(resolver.rotateLettersBy18("abc")) == "klm")
    }
}

@Suite("Kodik extractSourceCandidates")
struct KodikExtractSourceCandidatesTests {
    private var resolver: KodikVideoLinksResolver { makeResolver() }

    @Test func arrayOfObjectsYieldsEverySource() {
        let raw: Any = [["src": "a"], ["src": "b"], ["other": "c"]]
        #expect(resolver.extractSourceCandidates(from: raw) == ["a", "b"])
    }

    @Test func singleObjectWithStringSource() {
        #expect(resolver.extractSourceCandidates(from: ["src": "a"] as Any) == ["a"])
    }

    @Test func singleObjectWithArraySource() {
        #expect(resolver.extractSourceCandidates(from: ["src": ["a", "b"]] as Any) == ["a", "b"])
    }

    @Test func objectWithoutSourceKeyYieldsNothing() {
        #expect(resolver.extractSourceCandidates(from: ["href": "a"] as Any).isEmpty)
    }

    @Test func plainArrayOfStrings() {
        #expect(resolver.extractSourceCandidates(from: ["a", "b"] as Any) == ["a", "b"])
    }

    @Test func bareStringIsASingleCandidate() {
        #expect(resolver.extractSourceCandidates(from: "a" as Any) == ["a"])
    }

    @Test func unsupportedShapesYieldNothing() {
        #expect(resolver.extractSourceCandidates(from: 42 as Any).isEmpty)
        #expect(resolver.extractSourceCandidates(from: NSNull() as Any).isEmpty)
        #expect(resolver.extractSourceCandidates(from: [1, 2] as Any).isEmpty)
    }

    @Test func decodesTheShapeSeenInTheWild() throws {
        // The `links` payload as it arrives from /ftor: {"360": [{"src": ...}]}
        let json = #"{"360":[{"src":"\#(Fixture.base64A)","type":"application/x-mpegURL"}]}"#
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        let links = try #require(parsed as? [String: Any])
        let raw = try #require(links["360"])
        let candidates = resolver.extractSourceCandidates(from: raw)
        #expect(candidates == [Fixture.base64A])
        #expect(resolver.decodeSourceURL(from: candidates[0])?.urlString == "https://cdn.example.com/hls/master.m3u8")
    }
}
