//
//  SubtitleEndpointConfig.swift
//  MyShikiPlayer
//

import Foundation

/// Decoded and decrypted endpoint coordinates returned by the config fetch.
struct SubtitleEndpointConfig: Codable, Sendable, Equatable {
  /// Base URL for subtitle media files (ASS, VTT).
  let host: String
  /// Base URL for the Anime365 REST API.
  let api: String
}

// MARK: - Raw JSON shape from the remote config file

/// Wire format of the remote config JSON.
/// Both fields are XOR-encrypted strings that must be decrypted with the inner key.
struct SubtitleEndpointConfigRaw: Decodable, Sendable {
  let host: String
  let api: String
}
