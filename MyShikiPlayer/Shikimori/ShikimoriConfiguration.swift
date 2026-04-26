//
//  ShikimoriConfiguration.swift
//  MyShikiPlayer
//

import Foundation

struct ShikimoriConfiguration: Sendable {
    /// REST + GraphQL API base, e.g. https://shikimori.me
    var apiBaseURL: URL
    /// OAuth token host, e.g. https://shikimori.one
    var oauthBaseURL: URL
    /// OAuth application name — required in User-Agent
    var userAgentAppName: String
    var clientId: String
    var clientSecret: String
    var redirectURI: String
    /// Optional Bearer for authenticated REST/GraphQL
    var accessToken: String?

    var userAgentHeaderValue: String {
        userAgentAppName
    }

    nonisolated init(
        apiBaseURL: URL,
        oauthBaseURL: URL,
        userAgentAppName: String,
        clientId: String,
        clientSecret: String,
        redirectURI: String,
        accessToken: String? = nil
    ) {
        self.apiBaseURL = apiBaseURL
        self.oauthBaseURL = oauthBaseURL
        self.userAgentAppName = userAgentAppName
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.accessToken = accessToken
    }
}

extension ShikimoriConfiguration {
    /// Reads keys injected via xcconfig → Generated Info.plist (see project build settings).
    /// Applies user overrides from `ShikimoriHostsStore` on top — that's the
    /// single source of truth for host resolution in production code.
    nonisolated static func fromMainBundle(_ bundle: Bundle = .main) -> ShikimoriConfiguration? {
        func string(_ key: String) -> String? {
            (bundle.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard
            let apiString = string("ShikimoriBaseURL"),
            let apiURL = URL(string: apiString),
            let oauthString = string("ShikimoriOAuthBaseURL"),
            let oauthURL = URL(string: oauthString),
            let appName = string("ShikimoriUserAgentAppName"), !appName.isEmpty
        else { return nil }

        let clientId = string("ShikimoriClientID") ?? ""
        let clientSecret = string("ShikimoriClientSecret") ?? ""
        let redirect = string("ShikimoriRedirectURI") ?? ""

        // Apply user overrides last so they win over xcconfig defaults.
        let resolvedAPI = ShikimoriHostsStore.resolvedURL(
            for: .api,
            xcconfigDefault: apiURL
        )
        let resolvedOAuth = ShikimoriHostsStore.resolvedURL(
            for: .oauth,
            xcconfigDefault: oauthURL
        )

        return ShikimoriConfiguration(
            apiBaseURL: resolvedAPI,
            oauthBaseURL: resolvedOAuth,
            userAgentAppName: appName,
            clientId: clientId,
            clientSecret: clientSecret,
            redirectURI: redirect
        )
    }

    /// Convenience used everywhere the codebase needs "the live config".
    /// Bundles xcconfig defaults + UserDefaults overrides via
    /// `fromMainBundle()`. When the bundle is missing/incomplete (previews,
    /// tests, dev builds), falls back to `testing()` so call sites never
    /// segfault on `!`.
    nonisolated static func current(_ bundle: Bundle = .main) -> ShikimoriConfiguration {
        fromMainBundle(bundle) ?? testing()
    }

    /// Fallback for previews/tests when Info.plist keys are missing.
    nonisolated static func testing(
        apiBaseURL: URL = URL(string: "https://shikimori.me")!,
        oauthBaseURL: URL = URL(string: "https://shikimori.one")!,
        userAgentAppName: String = "MyShikiPlayerTests",
        clientId: String = "test_id",
        clientSecret: String = "test_secret",
        redirectURI: String = "myshikiplayer://oauth",
        accessToken: String? = nil
    ) -> ShikimoriConfiguration {
        ShikimoriConfiguration(
            apiBaseURL: apiBaseURL,
            oauthBaseURL: oauthBaseURL,
            userAgentAppName: userAgentAppName,
            clientId: clientId,
            clientSecret: clientSecret,
            redirectURI: redirectURI,
            accessToken: accessToken
        )
    }

    /// Title page on the Shikimori website (host taken from the OAuth base, usually matches the web catalog).
    func webURLForAnime(shikimoriId: Int) -> URL {
        oauthBaseURL
            .appendingPathComponent("animes")
            .appendingPathComponent(String(shikimoriId))
    }
}

// MARK: - Hosts override storage

/// User-overridable Shikimori hosts persisted in `UserDefaults`.
/// Both `api` and `oauth` keys default to whatever the xcconfig provided —
/// an empty / invalid override silently falls back to that default, so the
/// app keeps working if the user clears the field.
enum ShikimoriHostsStore {
    enum Field: String {
        case api
        case oauth

        var defaultsKey: String {
            switch self {
            case .api: return "settings.hosts.shikimori.api"
            case .oauth: return "settings.hosts.shikimori.oauth"
            }
        }
    }

    /// Builds the effective base URL for the given field, applying the user
    /// override on top of `xcconfigDefault`.
    static func resolvedURL(
        for field: Field,
        xcconfigDefault: URL,
        defaults: UserDefaults = .standard
    ) -> URL {
        let raw = defaults.string(forKey: field.defaultsKey)
        return overrideURL(raw: raw) ?? xcconfigDefault
    }

    /// Parses a raw user-supplied host into an `https://host` URL. Accepts
    /// either bare hosts ("shikimori.me") or full URLs ("https://shikimori.me").
    /// Returns nil for empty / malformed input — caller falls back to default.
    static func overrideURL(raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var working = trimmed
        // Tolerate a copy-pasted full URL.
        if let range = working.range(of: "://") {
            working = String(working[range.upperBound...])
        }
        if let slash = working.firstIndex(of: "/") {
            working = String(working[..<slash])
        }
        guard isValidHostLike(working) else { return nil }
        return URL(string: "https://\(working)")
    }

    static func isValidHostLike(_ value: String) -> Bool {
        guard !value.isEmpty, value.contains(".") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Mirrors `KodikHostsStore.isAcceptableInput` for the Settings TextField:
    /// empty input is OK (means "use default"); non-empty must be host-like.
    static func isAcceptableInput(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return overrideURL(raw: trimmed) != nil
    }

    /// Bare host string for the given field — used for things like the OAuth
    /// host displayed in Settings as a placeholder.
    static func currentHostString(
        for field: Field,
        xcconfigDefault: URL,
        defaults: UserDefaults = .standard
    ) -> String {
        let url = resolvedURL(for: field, xcconfigDefault: xcconfigDefault, defaults: defaults)
        return url.host ?? xcconfigDefault.host ?? ""
    }
}
