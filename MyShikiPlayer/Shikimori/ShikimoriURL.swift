//
//  ShikimoriURL.swift
//  MyShikiPlayer
//

import Foundation

/// Single resolver for "shikimori-shaped" URL strings. Honours the user's
/// host overrides via `ShikimoriConfiguration.current()` so the entire app
/// follows whatever host the user typed in Settings.
enum ShikimoriURL {
    /// Builds a web URL by joining `path` with the active OAuth/web base.
    /// Pass paths like `"/animes/12345"` (leading slash optional).
    static func web(
        path: String,
        configuration: ShikimoriConfiguration = .current()
    ) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        // String concat preserves query (`?...`) and fragment (`#...`) as-is.
        // `URL.appendingPathComponent` would percent-encode `?` to `%3F`,
        // which breaks Shikimori screenshot URLs that carry cache-busting
        // timestamps like `/system/.../1.jpg?1700000000`.
        let suffix = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        var base = configuration.oauthBaseURL.absoluteString
        if base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + suffix)
    }

    /// Same as `web(path:)` but for media (avatars, posters, screenshots).
    /// Today this also lives on the OAuth/web host; isolated as a separate
    /// entry-point so we can flip it to `apiBaseURL` later if the CDN host
    /// ever splits from the web host.
    static func media(
        path: String,
        configuration: ShikimoriConfiguration = .current()
    ) -> URL? {
        web(path: path, configuration: configuration)
    }
}

extension String {
    /// Resolves a raw Shikimori URL string into a `URL`:
    /// - Absolute (`http://`, `https://`) → returned as-is.
    /// - Path starting with `/` → joined with the active web host (honours
    ///   user override; default falls back to xcconfig).
    /// - Otherwise → best-effort `URL(string:)`.
    /// Used for poster and avatar fields that may come back as bare paths.
    var shikimoriResolvedURL: URL? {
        if hasPrefix("http://") || hasPrefix("https://") { return URL(string: self) }
        if hasPrefix("/") { return ShikimoriURL.media(path: self) }
        return URL(string: self)
    }

    /// Forces `http://` URLs to `https://`. Used for absolute media URLs from
    /// third-party CDNs that occasionally come back as plaintext while the app
    /// runs under ATS/HTTPS-only.
    var upgradedToHTTPS: URL? {
        if hasPrefix("http://") {
            return URL(string: "https://" + dropFirst("http://".count))
        }
        return URL(string: self)
    }
}
