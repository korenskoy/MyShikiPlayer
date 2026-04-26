//
//  KodikTokenManager.swift
//  MyShikiPlayer
//

import Foundation

enum KodikTokenManager {
    static func resolveToken() -> String? {
        let defaultsRaw = UserDefaults.standard.string(forKey: "kodik.apiToken")
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
        let line = "kodik_token resolve source=\(source) len=\(length)\(extra)"
        // Sync resolveToken() is called from non-isolated contexts; hop to the
        // main actor without blocking the caller. Order vs. surrounding log
        // events may shift by a tick, which is acceptable for diagnostics.
        Task { @MainActor in
            NetworkLogStore.shared.logUIEvent(line)
        }
    }
}
