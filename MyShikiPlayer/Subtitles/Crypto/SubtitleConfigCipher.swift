//
//  SubtitleConfigCipher.swift
//  MyShikiPlayer
//

import Foundation

/// Two-layer XOR + Base64 cipher used to protect endpoint configuration blobs.
///
/// Both layers use the same algorithm: Base64-decode → XOR cyclic with UTF-8 key → UTF-8 string.
/// The outer key is constant; the inner key is obtained by decrypting `encInnerXorKeyB64`
/// with the outer key.
enum SubtitleConfigCipher {

  // MARK: - Constants

  /// Outer XOR key used to decrypt both `encEndpointUrlB64` and `encInnerXorKeyB64`.
  static let outerKey = "MyShikiP1@yer"

  /// Encrypted endpoint config URL, Base64-encoded after XOR with `outerKey`.
  static let encEndpointUrlB64 =
    "JQ0nGBpRRn9QLhAJEy8BfQ8AHwElU24QCl0MFzokCAkxf1guHwpdPgwxGwUKC35bMxYL"

  /// Encrypted inner XOR key (used by the config JSON values), Base64-encoded after XOR with `outerKey`.
  static let encInnerXorKeyB64 = "HgwRXykJ"

  // MARK: - Core transform

  /// Decrypts a Base64-encoded XOR-ciphered string with the given UTF-8 key.
  ///
  /// Algorithm: Base64-decode → XOR each byte cyclically with the key bytes → interpret as UTF-8.
  /// Returns nil if decoding fails.
  static func decrypt(_ base64Encoded: String, key: String) -> String? {
    guard let cipherData = Data(base64Encoded: base64Encoded) else { return nil }
    let keyBytes = Array(key.utf8)
    guard !keyBytes.isEmpty else { return nil }
    var output = [UInt8](repeating: 0, count: cipherData.count)
    cipherData.withUnsafeBytes { ptr in
      for i in 0..<ptr.count {
        output[i] = ptr[i] ^ keyBytes[i % keyBytes.count]
      }
    }
    return String(bytes: output, encoding: .utf8)
  }

  /// Encrypts a UTF-8 string with the given key, returning Base64.
  ///
  /// Inverse of `decrypt(_:key:)`.
  static func encrypt(_ plaintext: String, key: String) -> String {
    let plainBytes = Array(plaintext.utf8)
    let keyBytes = Array(key.utf8)
    guard !keyBytes.isEmpty else { return Data(plainBytes).base64EncodedString() }
    var output = [UInt8](repeating: 0, count: plainBytes.count)
    for i in 0..<plainBytes.count {
      output[i] = plainBytes[i] ^ keyBytes[i % keyBytes.count]
    }
    return Data(output).base64EncodedString()
  }

  // MARK: - High-level helpers

  /// Decrypts the endpoint config URL using the outer key.
  static func decryptEndpointUrl() -> String? {
    decrypt(encEndpointUrlB64, key: outerKey)
  }

  /// Decrypts the inner XOR key using the outer key.
  static func decryptInnerXorKey() -> String? {
    decrypt(encInnerXorKeyB64, key: outerKey)
  }

  /// Decrypts a config JSON field value (host or api) using the inner key.
  static func decryptConfigField(_ base64Encoded: String, innerKey: String) -> String? {
    decrypt(base64Encoded, key: innerKey)
  }
}
