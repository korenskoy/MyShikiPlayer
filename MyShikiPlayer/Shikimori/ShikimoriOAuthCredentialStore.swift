//
//  ShikimoriOAuthCredentialStore.swift
//  MyShikiPlayer
//

import Foundation
import Security

enum ShikimoriKeychainError: Error {
    case unexpectedStatus(OSStatus)
    case dataConversion
}

/// Stores OAuth tokens in the Keychain (no iCloud sync).
final class ShikimoriOAuthCredentialStore: Sendable {
    private let service: String
    private let account = "shikimori.oauth"

    init(service: String? = nil) {
        self.service = service ?? Bundle.main.bundleIdentifier ?? "ru.korenskoy.MyShikiPlayer"
    }

    func load() throws -> OAuthCredential? {
        var item: CFTypeRef?
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrSynchronizable as String: false,
        ]
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ShikimoriKeychainError.unexpectedStatus(status) }
        guard let data = item as? Data else { throw ShikimoriKeychainError.dataConversion }
        return try JSONDecoder().decode(OAuthCredential.self, from: data)
    }

    func save(_ credential: OAuthCredential) throws {
        let data = try JSONEncoder().encode(credential)
        // The app has no background fetch / wake-from-lock requirements, so
        // `WhenUnlockedThisDeviceOnly` is the right tier — keys are only
        // accessible while the device is unlocked.
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
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw ShikimoriKeychainError.unexpectedStatus(updateStatus)
        }
        var add = lookup
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw ShikimoriKeychainError.unexpectedStatus(addStatus) }
    }

    func clear() throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ShikimoriKeychainError.unexpectedStatus(status)
        }
    }
}
