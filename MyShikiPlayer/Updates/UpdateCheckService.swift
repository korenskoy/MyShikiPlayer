//
//  UpdateCheckService.swift
//  MyShikiPlayer
//
//  Lightweight notifier for new GitHub Releases. The app is unsigned/notarized
//  for personal distribution, so we do NOT auto-download or install — we only
//  surface "version X.Y.Z is available" and link to the release page.
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

    private static let releasePublishedDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let jsonDecoder = JSONDecoder()

    private let session: URLSession
    private let userDefaults: UserDefaults
    private var isChecking = false

    /// Throttle so multiple window appearances within a session don't spam the
    /// public API (60 req/h per IP unauthenticated). One real check per ~6h is
    /// plenty for a "new release out" banner.
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

        let endpoint = "https://api.github.com/repos/\(Self.repoOwner)/\(Self.repoName)/releases/latest"
        guard let url = URL(string: endpoint) else { return }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
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

        // Stamp the timestamp regardless of HTTP outcome so a 404 (no
        // releases yet) or 403 (rate limit) doesn't make us retry on every
        // window appearance.
        userDefaults.set(Date(), forKey: DefaultsKey.lastCheckAt)

        guard http?.statusCode == 200 else { return }

        do {
            let release = try Self.jsonDecoder.decode(GitHubRelease.self, from: data)
            apply(release)
        } catch {
            NetworkLogStore.shared.logAppError("update_check_decode_failed: \(error.localizedDescription)")
        }
    }

    func skipCurrentlyOffered() {
        guard let info = availableUpdate else { return }
        userDefaults.set(info.version, forKey: DefaultsKey.skippedVersion)
        availableUpdate = nil
        NetworkLogStore.shared.logUIEvent("update_skipped \(info.version)")
    }

    // MARK: - Internal

    private func apply(_ release: GitHubRelease) {
        guard !release.draft, !release.prerelease else {
            availableUpdate = nil
            return
        }
        let normalized = Self.normalize(release.tagName)
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
        let trimmedName = release.name?.trimmingCharacters(in: .whitespaces) ?? ""
        let title = trimmedName.isEmpty ? release.tagName : trimmedName
        let url = URL(string: release.htmlUrl)
            ?? URL(string: "https://github.com/\(Self.repoOwner)/\(Self.repoName)/releases")!
        availableUpdate = AvailableUpdate(
            version: normalized,
            displayName: title,
            releaseURL: url,
            publishedAt: release.publishedAt.flatMap { Self.releasePublishedDateFormatter.date(from: $0) }
        )
        NetworkLogStore.shared.logUIEvent("update_available \(normalized)")
    }

    static func normalize(_ tag: String) -> String {
        tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
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

private struct GitHubRelease: Decodable {
    let tagName: String
    let name: String?
    let htmlUrl: String
    let draft: Bool
    let prerelease: Bool
    let publishedAt: String?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlUrl = "html_url"
        case draft
        case prerelease
        case publishedAt = "published_at"
    }
}
