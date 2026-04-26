//
//  KodikConfiguration.swift
//  MyShikiPlayer
//
//  Runtime-overridable Kodik hosts. Defaults match the original hardcoded
//  values; user overrides come from UserDefaults (Settings → "Домены").
//
//  Keys:
//   - settings.hosts.kodik.api      — API host, default "kodik-api.com"
//   - settings.hosts.kodik.referer  — Referer host, default "shikimori.io"
//
//  Resolution policy:
//   * Empty / whitespace-only / non-host string → fall back to default.
//   * Stored value is sanitised (trimmed, scheme stripped, trailing slash
//     stripped) so the rest of the codebase can build URLs as
//     `"https://\(configuration.apiHost)/..."` without re-validating.
//

import Foundation

public struct KodikConfiguration: Sendable, Equatable {
    public let apiHost: String
    public let refererHost: String
    public let scheme: String

    public init(apiHost: String, refererHost: String, scheme: String = "https") {
        self.apiHost = apiHost
        self.refererHost = refererHost
        self.scheme = scheme
    }

    public static let `default` = KodikConfiguration(
        apiHost: "kodik-api.com",
        refererHost: "shikimori.io",
        scheme: "https"
    )

    /// Reads the latest values from `UserDefaults` and falls back to defaults
    /// for any key that is missing or invalid. Cheap — a couple of dictionary
    /// lookups; safe to call on every request.
    public static func current(_ defaults: UserDefaults = .standard) -> KodikConfiguration {
        KodikConfiguration(
            apiHost: KodikHostsStore.normalizedHost(
                defaults.string(forKey: KodikHostsStore.Keys.api),
                fallback: KodikConfiguration.default.apiHost
            ),
            refererHost: KodikHostsStore.normalizedHost(
                defaults.string(forKey: KodikHostsStore.Keys.referer),
                fallback: KodikConfiguration.default.refererHost
            ),
            scheme: KodikConfiguration.default.scheme
        )
    }

    /// `https://shikimori.io/` style — used as the `Referer` header by the
    /// Kodik HTML/JSON scrapers.
    public var refererURLString: String {
        "\(scheme)://\(refererHost)/"
    }
}

/// Storage façade so Settings UI does not poke at `UserDefaults` keys
/// directly. Validation lives here too.
public enum KodikHostsStore {
    public enum Keys {
        public static let api = "settings.hosts.kodik.api"
        public static let referer = "settings.hosts.kodik.referer"
    }

    /// Normalises raw user input into a bare host (no scheme, no path, no
    /// trailing slash). Returns `fallback` when the input is empty / not a
    /// usable host.
    public static func normalizedHost(_ raw: String?, fallback: String) -> String {
        guard let raw else { return fallback }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }

        // Strip scheme if user pasted a full URL.
        var working = trimmed
        if let schemeRange = working.range(of: "://") {
            working = String(working[schemeRange.upperBound...])
        }
        // Strip trailing slash & path.
        if let slash = working.firstIndex(of: "/") {
            working = String(working[..<slash])
        }
        // Strip port for sanity ("kodik-api.com:443" → "kodik-api.com").
        // Hosts with ports are unusual for these APIs; if a user wants one,
        // they can keep the port — but make sure it parses as a hostname.
        guard isValidHostLike(working) else { return fallback }
        return working
    }

    /// Lightweight host validation: at least one dot, only [A-Za-z0-9.-:].
    public static func isValidHostLike(_ value: String) -> Bool {
        guard !value.isEmpty, value.contains(".") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// True if the field value (as the user typed it) is acceptable, used by
    /// the Settings TextField for inline validation. An empty string is
    /// treated as "use default" and is therefore acceptable.
    public static func isAcceptableInput(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        var working = trimmed
        if let schemeRange = working.range(of: "://") {
            working = String(working[schemeRange.upperBound...])
        }
        if let slash = working.firstIndex(of: "/") {
            working = String(working[..<slash])
        }
        return isValidHostLike(working)
    }
}
