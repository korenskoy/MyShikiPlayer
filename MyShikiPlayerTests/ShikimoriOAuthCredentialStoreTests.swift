//
//  ShikimoriOAuthCredentialStoreTests.swift
//  MyShikiPlayerTests
//
//  Each test uses a unique service-string so concurrent runs don't collide
//  with the production keychain entry or with each other. The teardown calls
//  `clear()` to remove the test entry from the user's login keychain.
//

import Foundation
import Security
import Testing
@testable import MyShikiPlayer

private func makeUniqueService() -> String {
    "ru.korenskoy.MyShikiPlayer.tests.\(UUID().uuidString)"
}

@Suite("ShikimoriOAuthCredentialStore", .serialized)
struct ShikimoriOAuthCredentialStoreTests {
    @Test func loadOnEmptyKeychainReturnsNil() throws {
        let store = ShikimoriOAuthCredentialStore(service: makeUniqueService())
        #expect(try store.load() == nil)
        try store.clear()
    }

    @Test func saveThenLoadReturnsSameCredential() throws {
        let service = makeUniqueService()
        let store = ShikimoriOAuthCredentialStore(service: service)
        defer { try? store.clear() }

        let original = OAuthCredential(
            accessToken: "access-XYZ",
            refreshToken: "refresh-ABC",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        try store.save(original)

        let loaded = try store.load()
        #expect(loaded == original)
    }

    @Test func saveOverwritesPreviousCredential() throws {
        // P1.19 — `save` must atomically update an existing slot. A second
        // save must replace the first, not append or fail.
        let service = makeUniqueService()
        let store = ShikimoriOAuthCredentialStore(service: service)
        defer { try? store.clear() }

        try store.save(OAuthCredential(
            accessToken: "v1",
            refreshToken: nil,
            expiresAt: nil
        ))
        try store.save(OAuthCredential(
            accessToken: "v2",
            refreshToken: "r2",
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000)
        ))

        let loaded = try store.load()
        #expect(loaded?.accessToken == "v2")
        #expect(loaded?.refreshToken == "r2")
    }

    @Test func clearRemovesEntry() throws {
        let service = makeUniqueService()
        let store = ShikimoriOAuthCredentialStore(service: service)
        try store.save(OAuthCredential(
            accessToken: "tok",
            refreshToken: nil,
            expiresAt: nil
        ))
        try store.clear()
        #expect(try store.load() == nil)
    }

    @Test func clearOnEmptyKeychainDoesNotThrow() throws {
        let store = ShikimoriOAuthCredentialStore(service: makeUniqueService())
        // No save before clear — must not throw on `errSecItemNotFound`.
        try store.clear()
    }

    @Test func savedItemIsNotSynchronizable() throws {
        // The saved entry must stay local to this device — never synced to
        // iCloud — regardless of which accessibility tier is in use. macOS's
        // SecItemCopyMatching is reliable about returning `synchronizable`
        // (unlike `accessible`, which is platform-quirky), so we lock that
        // invariant.
        let service = makeUniqueService()
        let store = ShikimoriOAuthCredentialStore(service: service)
        defer { try? store.clear() }

        try store.save(OAuthCredential(accessToken: "a", refreshToken: nil, expiresAt: nil))

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "shikimori.oauth",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        #expect(status == errSecSuccess)
        guard let attrs = item as? [String: Any] else {
            Issue.record("Expected dictionary attributes")
            return
        }
        let synchronizable = attrs[kSecAttrSynchronizable as String] as? Bool
        // Either "false" or absent — both mean local-only on macOS.
        #expect(synchronizable != true)
    }
}
