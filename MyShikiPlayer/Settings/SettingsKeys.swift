//
//  SettingsKeys.swift
//  MyShikiPlayer
//
//  Single source of truth for UserDefaults keys shared between the Settings
//  UI (@AppStorage) and the runtime that reads the same value (PlaybackSession,
//  diagnostics, etc.). Hand-typed strings on both sides drift silently — a
//  misspelled key compiles fine and quietly disables the feature.
//

import Foundation

enum SettingsKeys {
    /// Auto-skip both opening and ending chapters when the source provides
    /// time-coded ranges. Default is `false` so the toggle is fully opt-in.
    /// Renamed from the original `settings.autoSkipIntros` because the toggle
    /// covers ending too — the legacy key was never user-visible (default off,
    /// no production data) so the rename is a no-op for existing installs.
    static let autoSkipChapters = "settings.autoSkipChapters"
}
