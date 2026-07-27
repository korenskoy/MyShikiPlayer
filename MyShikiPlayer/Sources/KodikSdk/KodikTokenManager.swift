//
//  KodikTokenManager.swift
//  MyShikiPlayer
//

import Foundation

enum KodikTokenManager {
    /// Pre-Keychain storage location. Nothing writes it any more — it only
    /// feeds the one-shot migration below.
    static let legacyDefaultsKey = "kodik.apiToken"

    /// Resolution order: Keychain (user value) → legacy UserDefaults copy →
    /// Info.plist bundle token. The user value keeps winning over the bundled
    /// one, as before.
    static func resolveToken(
        store: KodikTokenStore = .shared,
        defaults: UserDefaults = .standard
    ) -> String? {
        migrateLegacyTokenIfNeeded(store: store, defaults: defaults)

        if let keychainToken = store.load() {
            logResolution(source: "keychain", length: keychainToken.count)
            return keychainToken
        }

        // Reachable only when the Keychain write failed during migration: the
        // plaintext value is deliberately left in place rather than dropped, so
        // a locked / broken Keychain cannot lose the user's token.
        let defaultsRaw = defaults.string(forKey: legacyDefaultsKey)
        let defaultsToken = defaultsRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let defaultsToken, !defaultsToken.isEmpty {
            logResolution(source: "defaults", length: defaultsToken.count)
            return defaultsToken
        }

        let bundleRaw = Bundle.main.object(forInfoDictionaryKey: "KodikAPIToken") as? String
        let bundleToken = bundleRaw?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let bundleToken, !bundleToken.isEmpty {
            logResolution(source: "bundle", length: bundleToken.count)
            return bundleToken
        }

        // Diagnostics: tell apart "key absent" from "key present but empty/whitespace".
        let defaultsState = stateLabel(raw: defaultsRaw, trimmed: defaultsToken)
        let bundleState = stateLabel(raw: bundleRaw, trimmed: bundleToken)
        logResolution(source: "nil", length: 0, defaultsState: defaultsState, bundleState: bundleState)
        return nil
    }

    /// Moves the plaintext UserDefaults token into the Keychain exactly once.
    /// The defaults key is removed only after the Keychain accepted the value
    /// (or already held one), so a failed write degrades to "keep using the
    /// legacy copy" instead of logging the user out of Kodik.
    ///
    /// Also called from the Settings field, which reads the Keychain directly
    /// and would otherwise show an empty box while a legacy token is still in
    /// use.
    static func migrateLegacyTokenIfNeeded(
        store: KodikTokenStore = .shared,
        defaults: UserDefaults = .standard
    ) {
        guard defaults.object(forKey: legacyDefaultsKey) != nil else { return }
        let trimmed = defaults.string(forKey: legacyDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            defaults.removeObject(forKey: legacyDefaultsKey)
            return
        }
        // A Keychain entry always wins: it is the newer value, written by the
        // Settings field after a previous migration.
        if store.load() != nil {
            defaults.removeObject(forKey: legacyDefaultsKey)
            log("kodik_token migrate_skipped reason=keychain_already_set")
            return
        }
        guard store.save(trimmed) else {
            log("kodik_token migrate_failed reason=keychain_write")
            return
        }
        defaults.removeObject(forKey: legacyDefaultsKey)
        log("kodik_token migrated destination=keychain len=\(trimmed.count)")
    }

    private static func stateLabel(raw: String?, trimmed: String?) -> String {
        guard let raw else { return "absent" }
        if raw.isEmpty { return "empty" }
        if trimmed?.isEmpty == true { return "whitespace_only" }
        return "present"
    }

    private static func logResolution(
        source: String,
        length: Int,
        defaultsState: String? = nil,
        bundleState: String? = nil
    ) {
        let extra: String = {
            guard let defaultsState, let bundleState else { return "" }
            return " defaults=\(defaultsState) bundle=\(bundleState)"
        }()
        log("kodik_token resolve source=\(source) len=\(length)\(extra)")
    }

    private static func log(_ line: String) {
        // Sync resolveToken() is called from non-isolated contexts; hop to the
        // main actor without blocking the caller. Order vs. surrounding log
        // events may shift by a tick, which is acceptable for diagnostics.
        Task { @MainActor in
            NetworkLogStore.shared.logUIEvent(line)
        }
    }
}
