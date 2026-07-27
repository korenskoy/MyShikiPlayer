//
//  KodikTokenStoreTests.swift
//  MyShikiPlayerTests
//
//  Every test uses a unique keychain service and a throwaway UserDefaults
//  suite so the user's real Kodik token is never touched.
//

import Foundation
import Testing
@testable import MyShikiPlayer

private func makeUniqueService() -> String {
    "ru.korenskoy.MyShikiPlayer.tests.kodik.\(UUID().uuidString)"
}

/// Throwaway `UserDefaults` suite — the migration must never run against
/// `.standard`, which the host app also uses.
private struct TestDefaults {
    let suiteName: String
    let defaults: UserDefaults

    init() throws {
        let name = makeUniqueService()
        suiteName = name
        defaults = try #require(UserDefaults(suiteName: name))
    }

    func removeAll() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

@Suite("KodikTokenStore", .serialized)
struct KodikTokenStoreTests {
    @Test func loadOnEmptyKeychainReturnsNil() {
        let store = KodikTokenStore(service: makeUniqueService())
        defer { store.clear() }
        #expect(store.load() == nil)
    }

    @Test func saveThenLoadReturnsSameValue() {
        let store = KodikTokenStore(service: makeUniqueService())
        defer { store.clear() }

        #expect(store.save("kodik-token-123"))
        #expect(store.load() == "kodik-token-123")
    }

    @Test func saveOverwritesPreviousValue() {
        let store = KodikTokenStore(service: makeUniqueService())
        defer { store.clear() }

        #expect(store.save("v1"))
        #expect(store.save("v2"))
        #expect(store.load() == "v2")
    }

    @Test func clearRemovesValue() {
        let store = KodikTokenStore(service: makeUniqueService())
        #expect(store.save("to-be-removed"))
        #expect(store.clear())
        #expect(store.load() == nil)
    }

    @Test func clearOnEmptyKeychainSucceeds() {
        let store = KodikTokenStore(service: makeUniqueService())
        #expect(store.clear())
    }

    @Test func savingBlankValueClearsTheEntry() {
        let store = KodikTokenStore(service: makeUniqueService())
        defer { store.clear() }

        #expect(store.save("value"))
        #expect(store.save("   "))
        #expect(store.load() == nil)
    }

    @Test func storesForDifferentServicesDoNotCollide() {
        let first = KodikTokenStore(service: makeUniqueService())
        let second = KodikTokenStore(service: makeUniqueService())
        defer {
            first.clear()
            second.clear()
        }

        #expect(first.save("one"))
        #expect(second.load() == nil)
    }
}

@Suite("KodikTokenManager migration", .serialized)
struct KodikTokenManagerMigrationTests {
    @Test func legacyDefaultsTokenMovesIntoKeychain() throws {
        let store = KodikTokenStore(service: makeUniqueService())
        let suite = try TestDefaults()
        defer {
            store.clear()
            suite.removeAll()
        }

        suite.defaults.set("legacy-plaintext-token", forKey: KodikTokenManager.legacyDefaultsKey)

        let resolved = KodikTokenManager.resolveToken(store: store, defaults: suite.defaults)

        #expect(resolved == "legacy-plaintext-token")
        #expect(store.load() == "legacy-plaintext-token")
        #expect(suite.defaults.object(forKey: KodikTokenManager.legacyDefaultsKey) == nil)
    }

    @Test func keychainValueWinsOverLegacyDefaultsCopy() throws {
        let store = KodikTokenStore(service: makeUniqueService())
        let suite = try TestDefaults()
        defer {
            store.clear()
            suite.removeAll()
        }

        #expect(store.save("keychain-token"))
        suite.defaults.set("stale-legacy-token", forKey: KodikTokenManager.legacyDefaultsKey)

        let resolved = KodikTokenManager.resolveToken(store: store, defaults: suite.defaults)

        #expect(resolved == "keychain-token")
        #expect(store.load() == "keychain-token")
        #expect(suite.defaults.object(forKey: KodikTokenManager.legacyDefaultsKey) == nil)
    }

    @Test func blankLegacyValueIsDroppedWithoutTouchingTheKeychain() throws {
        let store = KodikTokenStore(service: makeUniqueService())
        let suite = try TestDefaults()
        defer {
            store.clear()
            suite.removeAll()
        }

        suite.defaults.set("   ", forKey: KodikTokenManager.legacyDefaultsKey)
        KodikTokenManager.migrateLegacyTokenIfNeeded(store: store, defaults: suite.defaults)

        #expect(store.load() == nil)
        #expect(suite.defaults.object(forKey: KodikTokenManager.legacyDefaultsKey) == nil)
    }

    @Test func migrationIsIdempotent() throws {
        let store = KodikTokenStore(service: makeUniqueService())
        let suite = try TestDefaults()
        defer {
            store.clear()
            suite.removeAll()
        }

        suite.defaults.set("legacy", forKey: KodikTokenManager.legacyDefaultsKey)
        KodikTokenManager.migrateLegacyTokenIfNeeded(store: store, defaults: suite.defaults)
        KodikTokenManager.migrateLegacyTokenIfNeeded(store: store, defaults: suite.defaults)

        #expect(store.load() == "legacy")
        #expect(suite.defaults.object(forKey: KodikTokenManager.legacyDefaultsKey) == nil)
    }

    @Test func bundleTokenIsUsedWhenNoUserValueExists() throws {
        // The Info.plist ships a fallback token; the resolver must still reach
        // it once Keychain and defaults are both empty.
        let store = KodikTokenStore(service: makeUniqueService())
        let suite = try TestDefaults()
        defer {
            store.clear()
            suite.removeAll()
        }

        let resolved = KodikTokenManager.resolveToken(store: store, defaults: suite.defaults)
        let bundleToken = (Bundle.main.object(forInfoDictionaryKey: "KodikAPIToken") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(resolved == (bundleToken?.isEmpty == false ? bundleToken : nil))
    }
}
