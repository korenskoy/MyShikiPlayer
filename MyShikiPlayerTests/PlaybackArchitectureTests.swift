//
//  PlaybackArchitectureTests.swift
//  MyShikiPlayerTests
//

import XCTest
@testable import MyShikiPlayer

@MainActor
final class PlaybackArchitectureTests: XCTestCase {
    func testWatchProgressStoreRoundtrip() {
        let store = WatchProgressStore()
        store.save(shikimoriId: 777, episode: 3, seconds: 125.5)

        let record = store.progress(shikimoriId: 777)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.episode, 3)
        XCTAssertEqual(record?.seconds ?? 0, 125.5, accuracy: 0.0001)
    }

    func testKodikTokenIsAvailableInBundle() {
        // Configuration/Secrets.xcconfig provides KODIK_API_TOKEN, which is
        // wired into Info.plist via Configuration/OAuthURLTypes.plist as
        // KodikAPIToken. If this assertion fails, either the secrets file is
        // missing or the plist key was dropped — playback would silently
        // wipe the dub picker on every refresh (see feedback memory
        // "Плеер и авторизация — устойчивость").
        UserDefaults.standard.removeObject(forKey: "kodik.apiToken")
        let token = KodikTokenManager.resolveToken()
        XCTAssertNotNil(token, "Bundle must provide KodikAPIToken; check Configuration/OAuthURLTypes.plist")
        XCTAssertFalse(token?.isEmpty ?? true, "KodikAPIToken must not be empty")
    }

    func testUnavailableAdapterThrows() async {
        do {
            _ = try await AnilibAdapter().resolve(
                request: SourceResolutionRequest(shikimoriId: 1, episode: 1, preferredTranslationId: nil)
            )
            XCTFail("Expected unavailable source error")
        } catch {
            XCTAssertTrue(error is PlayerError)
        }
    }
}
