//
//  KodikSkipRangeTests.swift
//  MyShikiPlayerTests
//

import Foundation
import Testing
@testable import MyShikiPlayer

@Suite("Kodik parseTimeToken")
struct KodikParseTimeTokenTests {
    @Test func plainSecondsParseAsDouble() {
        #expect(KodikVideoLinksResolver.parseTimeToken("90") == 90)
        #expect(KodikVideoLinksResolver.parseTimeToken("0") == 0)
        #expect(KodikVideoLinksResolver.parseTimeToken("3.5") == 3.5)
    }

    @Test func mmssCombinesMinutesAndSeconds() {
        #expect(KodikVideoLinksResolver.parseTimeToken("01:30") == 90.0)
        #expect(KodikVideoLinksResolver.parseTimeToken("00:00") == 0.0)
        // Cast composite Int expressions to Double — Optional<Double> == Int
        // resolves to a (silent) false comparison under Swift Testing.
        #expect(KodikVideoLinksResolver.parseTimeToken("21:45") == Double(21 * 60 + 45))
    }

    @Test func hhmmssCombinesHoursMinutesSeconds() {
        #expect(KodikVideoLinksResolver.parseTimeToken("01:00:00") == 3600.0)
        #expect(KodikVideoLinksResolver.parseTimeToken("01:23:45") == Double(3600 + 23 * 60 + 45))
    }

    @Test func whitespacePadIsTolerated() {
        #expect(KodikVideoLinksResolver.parseTimeToken("  01:30  ") == 90)
    }

    @Test func malformedTokensReturnNil() {
        #expect(KodikVideoLinksResolver.parseTimeToken("") == nil)
        #expect(KodikVideoLinksResolver.parseTimeToken("abc") == nil)
        #expect(KodikVideoLinksResolver.parseTimeToken("12:") == nil)
        #expect(KodikVideoLinksResolver.parseTimeToken(":30") == nil)
        // Four colon-separated chunks are unsupported.
        #expect(KodikVideoLinksResolver.parseTimeToken("01:02:03:04") == nil)
        // Non-numeric component falls through.
        #expect(KodikVideoLinksResolver.parseTimeToken("01:ab") == nil)
    }
}

@Suite("Kodik parseSkipRanges")
struct KodikParseSkipRangesTests {
    private static func wrap(_ payload: String) -> String {
        // Mirror the on-page JS shape parseSkipRanges scrapes.
        #"<script>parseSkipButtons("\#(payload)","opening,ending");</script>"#
    }

    @Test func twoPairsAreOpeningThenEnding() {
        let page = Self.wrap("00:00-01:30,21:00-22:30")
        let res = KodikVideoLinksResolver.parseSkipRanges(from: page)
        #expect(res.opening == 0...90)
        #expect(res.ending == (21 * 60.0)...(22 * 60.0 + 30))
    }

    @Test func singleEarlyRangeIsOpening() {
        // Range starting at 0:00 is too early to be an ending.
        let page = Self.wrap("00:00-01:30")
        let res = KodikVideoLinksResolver.parseSkipRanges(from: page)
        #expect(res.opening == 0...90)
        #expect(res.ending == nil)
    }

    @Test func singleLateRangeIsEnding() {
        // Range starting after the 5-minute heuristic cutoff is the ending.
        let page = Self.wrap("21:00-22:30")
        let res = KodikVideoLinksResolver.parseSkipRanges(from: page)
        #expect(res.opening == nil)
        #expect(res.ending == (21 * 60.0)...(22 * 60.0 + 30))
    }

    @Test func singleRangeAtCutoffClassifiedAsEnding() {
        // 5:00 == cutoff (300s) → goes to .ending (>= cutoff branch).
        let page = Self.wrap("05:00-06:00")
        let res = KodikVideoLinksResolver.parseSkipRanges(from: page)
        #expect(res.opening == nil)
        #expect(res.ending == 300...360)
    }

    @Test func extraPairsBeyondTwoAreIgnored() {
        let page = Self.wrap("00:00-01:30,21:00-22:30,99:00-99:30")
        let res = KodikVideoLinksResolver.parseSkipRanges(from: page)
        #expect(res.opening == 0...90)
        #expect(res.ending == (21 * 60.0)...(22 * 60.0 + 30))
    }

    @Test func invalidPairWhereStartAtOrPastEndIsDropped() {
        // start == end is invalid; start > end is invalid. Drop both.
        let page = Self.wrap("01:00-01:00,02:30-02:00")
        let res = KodikVideoLinksResolver.parseSkipRanges(from: page)
        #expect(res.opening == nil)
        #expect(res.ending == nil)
    }

    @Test func partiallyValidPairsKeepValidOnes() {
        // First pair is bogus → falls back to single-range heuristic on the second.
        let page = Self.wrap("00:00-00:00,21:00-22:30")
        let res = KodikVideoLinksResolver.parseSkipRanges(from: page)
        #expect(res.opening == nil)
        #expect(res.ending == (21 * 60.0)...(22 * 60.0 + 30))
    }

    @Test func pageWithoutMarkerReturnsBothNil() {
        let res = KodikVideoLinksResolver.parseSkipRanges(from: "<html>no markers</html>")
        #expect(res.opening == nil)
        #expect(res.ending == nil)
    }

    @Test func parseSkipButtonSingularSpellingAlsoMatches() {
        // Both `parseSkipButton(` and `parseSkipButtons(` are seen on Kodik pages.
        let page = #"<script>parseSkipButton("00:00-01:30","opening");</script>"#
        let res = KodikVideoLinksResolver.parseSkipRanges(from: page)
        #expect(res.opening == 0...90)
    }
}
