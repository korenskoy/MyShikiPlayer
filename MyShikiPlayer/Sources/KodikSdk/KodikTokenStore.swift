//
//  KodikTokenStore.swift
//  MyShikiPlayer
//

import Foundation
import Security

/// Keychain storage for the user-supplied Kodik API token (no iCloud sync).
/// Shape mirrors `ShikimoriOAuthCredentialStore`, but the API is non-throwing:
/// a Keychain hiccup must never break playback setup or the Settings screen,
/// so failures are logged and reported as `nil` / `false`.
///
/// The token value itself is never logged — only its length and the source it
/// was resolved from.
struct KodikTokenStore: Sendable {
    static let shared = KodikTokenStore()

    private let service: String
    private let account: String

    init(service: String? = nil, account: String = "kodik.apiToken") {
        self.service = service ?? Bundle.main.bundleIdentifier ?? "ru.korenskoy.MyShikiPlayer"
        self.account = account
    }

    func load() -> String? {
        var item: CFTypeRef?
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            log("load_failed status=\(status)")
            return nil
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            log("load_failed reason=decode")
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Empty (or whitespace-only) input clears the entry — the Settings field
    /// treats an empty string as "no token".
    @discardableResult
    func save(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return clear() }

        let data = Data(trimmed.utf8)
        // The app has no background fetch / wake-from-lock requirements, so
        // `WhenUnlockedThisDeviceOnly` is the right tier.
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
        // SecItemUpdate first → SecItemAdd on errSecItemNotFound. Avoids the
        // delete+add race window where a concurrent reader (or a crash between
        // the two calls) finds the slot empty.
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(lookup as CFDictionary, updateAttrs as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else {
            log("save_failed status=\(updateStatus)")
            return false
        }

        var add = lookup
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            log("save_failed status=\(addStatus)")
            return false
        }
        return true
    }

    @discardableResult
    func clear() -> Bool {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            log("clear_failed status=\(status)")
            return false
        }
        return true
    }

    private func log(_ message: String) {
        // Callers are synchronous and non-isolated; hop to the main actor
        // without blocking them.
        Task { @MainActor in
            NetworkLogStore.shared.logAppError("kodik_token_store \(message)")
        }
    }
}
