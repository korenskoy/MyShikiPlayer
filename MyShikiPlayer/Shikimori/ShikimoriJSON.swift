//
//  ShikimoriJSON.swift
//  MyShikiPlayer
//

import Foundation

enum ShikimoriJSON {
    /// Two read-only formatters so a shared decoder remains safe under
    /// concurrent decode calls (the decoder may be cached as `static let`
    /// at call sites). Mutating a single formatter's `formatOptions` mid-decode
    /// would race when multiple HTTP responses parse dates in parallel.
    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = isoWithFractional.date(from: str) { return date }
            if let date = isoBasic.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(str)")
        }
        return d
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(isoWithFractional.string(from: date))
        }
        return e
    }
}
