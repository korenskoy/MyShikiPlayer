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
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw ShikimoriKeychainError.unexpectedStatus(status) }
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
