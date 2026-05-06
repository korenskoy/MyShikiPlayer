//
//  UpdateCheckService.swift
//  MyShikiPlayer
//
//  Lightweight notifier for new GitHub Releases. The app is unsigned/notarized
//  for personal distribution, so we do NOT auto-download or install — we only
//  surface "version X.Y.Z is available" and link to the release page.
//
//  Source: the public GitHub Releases Atom feed
//  (https://github.com/<owner>/<repo>/releases.atom). Unlike api.github.com,
//  it is served via GitHub's CDN and is not subject to the 60 req/h
//  unauthenticated REST limit — important because many users share VPN
//  egress IPs and would otherwise collectively hit 403.
//

import Combine
import Foundation

struct AvailableUpdate: Equatable {
    let version: String       // Tag name with the leading "v" stripped.
    let displayName: String   // GitHub release title (falls back to the tag).
    let releaseURL: URL
    let publishedAt: Date?
}

@MainActor
final class UpdateCheckService: ObservableObject {
    static let shared = UpdateCheckService()

    @Published private(set) var availableUpdate: AvailableUpdate?

    /// Hardcoded — the release feed is a public artefact of this specific repo.
    /// Forks can change it here; there is no need to expose it in Settings.
    private static let repoOwner = "korenskoy"
    private static let repoName = "MyShikiPlayer"

    private enum DefaultsKey {
        static let lastCheckAt = "updates.lastCheckAt"
        static let skippedVersion = "updates.skippedVersion"
    }

    /// Atom feed timestamps are RFC 3339 / ISO8601 without fractional seconds
    /// (e.g. `2026-04-25T10:00:00Z`). Keep the formatter strict so we don't
    /// silently mis-parse anything weird.
    private static let releasePublishedDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private let session: URLSession
    private let userDefaults: UserDefaults
    private var isChecking = false

    /// Throttle so multiple window appearances within a session don't refetch
    /// the feed unnecessarily. One real check per ~6h is plenty for a
    /// "new release out" banner.
    private let minCheckInterval: TimeInterval = 6 * 60 * 60

    init(session: URLSession = .shared, userDefaults: UserDefaults = .standard) {
        self.session = session
        self.userDefaults = userDefaults
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    /// Fire-and-forget check. Errors are swallowed and logged to the diagnostics
    /// panel — a failed update probe must never bubble up to the user.
    func checkInBackground(force: Bool = false) async {
        if !force, let last = userDefaults.object(forKey: DefaultsKey.lastCheckAt) as? Date,
           Date().timeIntervalSince(last) < minCheckInterval {
            return
        }
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let endpoint = "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases.atom"
        guard let url = URL(string: endpoint) else { return }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")
        request.setValue("MyShikiPlayer/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let startedAt = Date()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            NetworkLogStore.shared.log(
                method: "GET",
                url: url,
                statusCode: nil,
                duration: Date().timeIntervalSince(startedAt),
                responseBytes: nil,
                responsePreview: nil,
                errorDescription: error.localizedDescription
            )
            return
        }

        let http = response as? HTTPURLResponse
        NetworkLogStore.shared.log(
            method: "GET",
            url: url,
            statusCode: http?.statusCode,
            duration: Date().timeIntervalSince(startedAt),
            responseBytes: data.count,
            responsePreview: NetworkLogStore.previewFromResponseData(data, maxBytes: 1024),
            errorDescription: nil
        )

        // Stamp only on definitive HTTP outcomes (2xx success, 404 means "no
        // releases yet"). Transient 5xx / 429 / network errors must NOT
        // suppress the next probe for 6h — that would mask GitHub's CDN
        // hiccups and freeze the update banner for half a day.
        let status = http?.statusCode
        let definitive = status.map { (200..<300).contains($0) || $0 == 404 } ?? false
        if definitive {
            userDefaults.set(Date(), forKey: DefaultsKey.lastCheckAt)
        }

        guard status == 200 else { return }

        guard let entry = ReleaseAtomParser.firstEntry(from: data) else {
            NetworkLogStore.shared.logAppError("update_check_parse_failed: empty or invalid atom feed")
            return
        }
        apply(entry)
    }

    func skipCurrentlyOffered() {
        guard let info = availableUpdate else { return }
        userDefaults.set(info.version, forKey: DefaultsKey.skippedVersion)
        availableUpdate = nil
        NetworkLogStore.shared.logUIEvent("update_skipped \(info.version)")
    }

    // MARK: - Internal

    private func apply(_ entry: ReleaseAtomEntry) {
        // The Atom feed exposes only published releases (drafts are private),
        // but it does NOT distinguish prereleases from final releases. We
        // approximate the old `release.prerelease` filter via tag convention.
        guard let tag = entry.tag else {
            availableUpdate = nil
            return
        }
        if Self.isPrereleaseTag(tag) {
            availableUpdate = nil
            NetworkLogStore.shared.logUIEvent("update_skipped_prerelease \(tag)")
            return
        }
        let normalized = Self.normalize(tag)
        guard Self.compareVersions(normalized, currentVersion) == .orderedDescending else {
            availableUpdate = nil
            return
        }
        // Only suppress when the user explicitly skipped THIS exact version (or
        // a newer one). A fresh release strictly newer than the skip mark
        // resurfaces the banner — that is the point of opting back in.
        if let skipped = userDefaults.string(forKey: DefaultsKey.skippedVersion),
           Self.compareVersions(normalized, skipped) != .orderedDescending {
            availableUpdate = nil
            return
        }
        let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? tag : trimmedTitle
        // Defence-in-depth: only trust release URLs that resolve to GitHub.
        // The Atom feed is a public artefact and a malicious mirror could
        // replace it; the banner click should never deep-link off-domain.
        let candidate = entry.url
            ?? URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases")
        guard let url = candidate, Self.isTrustedReleaseHost(url) else {
            NetworkLogStore.shared.logAppError(
                "update_check_untrusted_url \(candidate?.absoluteString ?? "nil")"
            )
            availableUpdate = nil
            return
        }
        availableUpdate = AvailableUpdate(
            version: normalized,
            displayName: title,
            releaseURL: url,
            publishedAt: entry.updated.flatMap { Self.releasePublishedDateFormatter.date(from: $0) }
        )
        NetworkLogStore.shared.logUIEvent("update_available \(normalized)")
    }

    static func normalize(_ tag: String) -> String {
        tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
    }

    /// Allow only the canonical GitHub domain (and its `*.github.com` family,
    /// which covers redirects through `objects.githubusercontent.com` etc.).
    /// Anything else came from a tampered or proxied feed.
    static func isTrustedReleaseHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com")
    }

    /// Recognise common prerelease tag suffixes — `-alpha`, `-beta`, `-rc`,
    /// `-pre`, `-dev` (case-insensitive, word-bounded). Matches `v1.0.0-rc.1`,
    /// `1.2-beta`, `2.0-DEV-3`; does not match `1.2.3-prefix-stable`.
    static func isPrereleaseTag(_ tag: String) -> Bool {
        tag.range(
            of: #"-(alpha|beta|rc|pre|dev)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    /// Component-wise numeric comparison so "1.10" > "1.2" works.
    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let r = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(l.count, r.count) {
            let a = index < l.count ? l[index] : 0
            let b = index < r.count ? r[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }
}

/// One `<entry>` from a GitHub releases Atom feed, normalised to the bits we
/// actually care about.
private struct ReleaseAtomEntry {
    let title: String
    let url: URL?
    /// Tag name extracted from the release URL (`.../releases/tag/<TAG>`).
    /// `nil` if the URL doesn't match that shape.
    let tag: String?
    /// Raw RFC 3339 timestamp from `<updated>`, parsed by the caller.
    let updated: String?
}

/// Streaming `XMLParser` delegate that returns the FIRST `<entry>` of a GitHub
/// releases Atom feed and aborts. The feed is sorted newest-first, so the
/// first entry is the latest release.
private final class ReleaseAtomParser: NSObject, XMLParserDelegate {
    static func firstEntry(from data: Data) -> ReleaseAtomEntry? {
        let delegate = ReleaseAtomParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.firstEntry
    }

    private(set) var firstEntry: ReleaseAtomEntry?

    private var inEntry = false
    /// Track the current open-element path. Using a stack (rather than a
    /// single string) means text after a nested close — e.g. `"baz"` in
    /// `<title>foo<b>bar</b>baz</title>` — is still attributed to `<title>`.
    private var elementStack: [String] = []
    private var currentTitle = ""
    private var currentHref = ""
    private var currentUpdated = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementStack.append(elementName)
        if elementName == "entry" {
            inEntry = true
            currentTitle = ""
            currentHref = ""
            currentUpdated = ""
            return
        }
        // GitHub's Atom feed has a single <link rel="alternate"> per entry
        // pointing at the human-readable release page. Treat a missing rel
        // as "alternate" per the Atom spec.
        if inEntry, elementName == "link", let href = attributeDict["href"] {
            let rel = attributeDict["rel"] ?? "alternate"
            if rel == "alternate" {
                currentHref = href
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inEntry, let current = elementStack.last else { return }
        switch current {
        case "title": currentTitle += string
        case "updated": currentUpdated += string
        default: break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        _ = elementStack.popLast()
        if elementName == "entry" {
            let url = URL(string: currentHref)
            firstEntry = ReleaseAtomEntry(
                title: currentTitle,
                url: url,
                tag: Self.extractTag(from: url),
                updated: currentUpdated.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            // First entry is the newest one — bail out instead of walking the
            // rest of the feed.
            parser.abortParsing()
        }
    }

    /// `https://github.com/<owner>/<repo>/releases/tag/<TAG>` → `<TAG>`.
    private static func extractTag(from url: URL?) -> String? {
        guard let url else { return nil }
        let components = url.pathComponents
        guard let tagIndex = components.firstIndex(of: "tag"),
              tagIndex + 1 < components.count else { return nil }
        let tag = components[tagIndex + 1]
        return tag.isEmpty ? nil : tag
    }
}
