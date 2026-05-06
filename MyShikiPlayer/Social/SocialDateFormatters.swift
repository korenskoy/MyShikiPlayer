//
//  SocialDateFormatters.swift
//  MyShikiPlayer
//

import Foundation

/// Shared date formatters used across the Social module. Cached as static
/// instances so a feed render of 100+ comments doesn't allocate one
/// `RelativeDateTimeFormatter` / `DateFormatter` per row per re-render.
enum SocialDateFormatters {
    static let relativeRu: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.unitsStyle = .short
        return f
    }()

    static let hhmmRu: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "HH:mm"
        return f
    }()
}
