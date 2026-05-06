//
//  UpdateCheckServiceTests.swift
//  MyShikiPlayerTests
//

import Foundation
import Testing
@testable import MyShikiPlayer

@MainActor
@Suite("UpdateCheckService.normalize")
struct UpdateNormalizeTests {
    @Test func stripsLowercaseVPrefix() {
        #expect(UpdateCheckService.normalize("v1.2.3") == "1.2.3")
    }

    @Test func stripsUppercaseVPrefix() {
        #expect(UpdateCheckService.normalize("V0.9") == "0.9")
    }

    @Test func leavesNonPrefixedTagAlone() {
        #expect(UpdateCheckService.normalize("1.0.0") == "1.0.0")
        #expect(UpdateCheckService.normalize("release-2026") == "release-2026")
    }

    @Test func emptyTagIsReturnedUnchanged() {
        #expect(UpdateCheckService.normalize("") == "")
    }
}

@MainActor
@Suite("UpdateCheckService.isPrereleaseTag")
struct UpdatePrereleaseTagTests {
    @Test func recognisesAlpha() {
        #expect(UpdateCheckService.isPrereleaseTag("v1.0.0-alpha") == true)
        #expect(UpdateCheckService.isPrereleaseTag("1.0.0-alpha.2") == true)
    }

    @Test func recognisesBetaRcPreDevCaseInsensitive() {
        #expect(UpdateCheckService.isPrereleaseTag("v1.0.0-beta") == true)
        #expect(UpdateCheckService.isPrereleaseTag("v1.0.0-BETA") == true)
        #expect(UpdateCheckService.isPrereleaseTag("v1.0.0-rc.1") == true)
        #expect(UpdateCheckService.isPrereleaseTag("v2.0-DEV-3") == true)
        #expect(UpdateCheckService.isPrereleaseTag("v1.0-pre") == true)
    }

    @Test func ignoresOtherSuffixes() {
        #expect(UpdateCheckService.isPrereleaseTag("v1.0.0") == false)
        #expect(UpdateCheckService.isPrereleaseTag("1.2.3-stable") == false)
        // Word boundary — `-prefix-stable` must not match `-pre` at start.
        #expect(UpdateCheckService.isPrereleaseTag("1.2.3-prefix-stable") == false)
    }
}

@MainActor
@Suite("UpdateCheckService.compareVersions")
struct UpdateCompareVersionsTests {
    @Test func componentwiseNumericComparison() {
        #expect(UpdateCheckService.compareVersions("1.10", "1.2") == .orderedDescending)
        #expect(UpdateCheckService.compareVersions("1.2", "1.10") == .orderedAscending)
        #expect(UpdateCheckService.compareVersions("1.0.0", "1.0.0") == .orderedSame)
    }

    @Test func differingArityTreatedAsZeroPadded() {
        // "1.2" == "1.2.0", "1.2.1" > "1.2"
        #expect(UpdateCheckService.compareVersions("1.2", "1.2.0") == .orderedSame)
        #expect(UpdateCheckService.compareVersions("1.2.1", "1.2") == .orderedDescending)
        #expect(UpdateCheckService.compareVersions("1", "1.0.0") == .orderedSame)
    }

    @Test func nonNumericChunksDegradeToZero() {
        #expect(UpdateCheckService.compareVersions("1.x", "1.0") == .orderedSame)
        // 2.0 > 1.x because 2 > 1
        #expect(UpdateCheckService.compareVersions("2.0", "1.x") == .orderedDescending)
    }
}

@MainActor
@Suite("UpdateCheckService.isTrustedReleaseHost")
struct UpdateTrustedHostTests {
    @Test func acceptsCanonicalGitHub() {
        let url = URL(string: "https://github.com/korenskoy/MyShikiPlayer/releases/tag/v1.2.3")!
        #expect(UpdateCheckService.isTrustedReleaseHost(url) == true)
    }

    @Test func rejectsGithubusercontentSibling() {
        // The Atom feed only links to release PAGES under github.com proper;
        // *.githubusercontent.com is a separate domain (artifact redirects) and
        // we deliberately don't trust it as the banner target.
        let url = URL(string: "https://objects.githubusercontent.com/file.dmg")!
        #expect(UpdateCheckService.isTrustedReleaseHost(url) == false)
    }

    @Test func acceptsApiSubdomain() {
        let url = URL(string: "https://api.github.com/repos")!
        #expect(UpdateCheckService.isTrustedReleaseHost(url) == true)
    }

    @Test func acceptsAnyGithubSubdomainAndIsCaseInsensitive() {
        let url = URL(string: "https://AVATARS.GITHUB.COM/u/1")!
        #expect(UpdateCheckService.isTrustedReleaseHost(url) == true)
    }

    @Test func rejectsNonGitHubHosts() {
        #expect(UpdateCheckService.isTrustedReleaseHost(URL(string: "https://example.com/x")!) == false)
        #expect(UpdateCheckService.isTrustedReleaseHost(URL(string: "https://attacker.io/x")!) == false)
        // Look-alike / suffix games — must be rejected.
        #expect(UpdateCheckService.isTrustedReleaseHost(URL(string: "https://github.com.attacker.io/x")!) == false)
        #expect(UpdateCheckService.isTrustedReleaseHost(URL(string: "https://nogithub.com/x")!) == false)
    }

    @Test func rejectsURLWithoutHost() {
        let url = URL(string: "file:///tmp/x")!
        #expect(UpdateCheckService.isTrustedReleaseHost(url) == false)
    }
}
