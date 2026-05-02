//
//  SubtitleConfigCipherTests.swift
//  MyShikiPlayerTests
//

import XCTest
@testable import MyShikiPlayer

final class SubtitleConfigCipherTests: XCTestCase {

  // MARK: - Round-trip

  func test_encryptDecryptRoundTrip() {
    let key = "testKey123"
    let plaintext = "hello world"
    let encrypted = SubtitleConfigCipher.encrypt(plaintext, key: key)
    let decrypted = SubtitleConfigCipher.decrypt(encrypted, key: key)
    XCTAssertEqual(decrypted, plaintext)
  }

  func test_encryptDecryptRoundTripWithOuterKey() {
    let plaintext = "https://example.com/config.json"
    let encrypted = SubtitleConfigCipher.encrypt(plaintext, key: SubtitleConfigCipher.outerKey)
    let decrypted = SubtitleConfigCipher.decrypt(encrypted, key: SubtitleConfigCipher.outerKey)
    XCTAssertEqual(decrypted, plaintext)
  }

  func test_encryptOfDecryptedEndpointUrlReproducesOriginal() throws {
    let decrypted = try XCTUnwrap(SubtitleConfigCipher.decryptEndpointUrl())
    let reEncrypted = SubtitleConfigCipher.encrypt(decrypted, key: SubtitleConfigCipher.outerKey)
    XCTAssertEqual(reEncrypted, SubtitleConfigCipher.encEndpointUrlB64)
  }

  func test_encryptOfDecryptedInnerKeyReproducesOriginal() throws {
    let decrypted = try XCTUnwrap(SubtitleConfigCipher.decryptInnerXorKey())
    let reEncrypted = SubtitleConfigCipher.encrypt(decrypted, key: SubtitleConfigCipher.outerKey)
    XCTAssertEqual(reEncrypted, SubtitleConfigCipher.encInnerXorKeyB64)
  }

  // MARK: - Golden vectors

  func test_decryptedEndpointUrlIsNonEmpty() throws {
    let url = try XCTUnwrap(SubtitleConfigCipher.decryptEndpointUrl())
    XCTAssertFalse(url.isEmpty)
  }

  func test_decryptedInnerKeyIsNonEmpty() throws {
    let key = try XCTUnwrap(SubtitleConfigCipher.decryptInnerXorKey())
    XCTAssertFalse(key.isEmpty)
  }

  // Base64: 8 chars encodes 6 bytes
  func test_decryptedInnerKeyHasExpectedLength() throws {
    let key = try XCTUnwrap(SubtitleConfigCipher.decryptInnerXorKey())
    XCTAssertEqual(key.utf8.count, 6)
  }

  // MARK: - Edge cases

  func test_decryptWithEmptyKeyReturnsNil() {
    let result = SubtitleConfigCipher.decrypt("AAAA", key: "")
    XCTAssertNil(result)
  }

  func test_decryptInvalidBase64ReturnsNil() {
    let result = SubtitleConfigCipher.decrypt("not-valid-base64!!!", key: "somekey")
    XCTAssertNil(result)
  }

  func test_emptyPlaintextRoundTrip() {
    let encrypted = SubtitleConfigCipher.encrypt("", key: "key")
    let decrypted = SubtitleConfigCipher.decrypt(encrypted, key: "key")
    XCTAssertEqual(decrypted, "")
  }
}
