//
//  SettingsHostsModel.swift
//  MyShikiPlayer
//
//  ObservableObject backing the "Домены" section of SettingsView. Keeps
//  drafts (typed-but-not-yet-saved values) separate from the stored
//  UserDefaults values, so we never write from a SwiftUI `body` and never
//  reflow the layout while the user types.
//
//  Persistence path:
//   * Each TextField has an `.onSubmit { commit(field) }` handler.
//   * Field-level focus loss in macOS routes through Submit too (Tab / Enter
//     / clicking outside the field) — sufficient for a small Settings sheet
//     without bringing in a debounce timer.
//   * Empty / whitespace-only / invalid → key is REMOVED → falls back to the
//     xcconfig default for Shikimori, or the hardcoded SDK default for Kodik.
//
//  The model never calls `signOut()` or `markRequiresReauth()` — host
//  changes must not invalidate Keychain credentials (see
//  feedback_player_resilience).
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class SettingsHostsModel: ObservableObject {
    enum Field: Hashable {
        case shikimoriAPI
        case shikimoriOAuth
        case kodikAPI
        case kodikReferer
    }

    // Drafts: published so TextField bindings re-render on edit, but writes to
    // UserDefaults happen only inside `commit(_:)` / `resetAll()` — never from
    // a `body` evaluation (feedback_no_side_effects_in_body).
    @Published var shikimoriAPIDraft: String = ""
    @Published var shikimoriOAuthDraft: String = ""
    @Published var kodikAPIDraft: String = ""
    @Published var kodikRefererDraft: String = ""

    @Published var savedFlash: Bool = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reloadFromDefaults()
    }

    func reloadFromDefaults() {
        shikimoriAPIDraft = defaults.string(forKey: ShikimoriHostsStore.Field.api.defaultsKey) ?? ""
        shikimoriOAuthDraft = defaults.string(forKey: ShikimoriHostsStore.Field.oauth.defaultsKey) ?? ""
        kodikAPIDraft = defaults.string(forKey: KodikHostsStore.Keys.api) ?? ""
        kodikRefererDraft = defaults.string(forKey: KodikHostsStore.Keys.referer) ?? ""
    }

    /// Default placeholder text for each TextField. Pulled from the live
    /// xcconfig + SDK defaults so the user always sees what the app will use
    /// if they leave the field empty.
    func placeholder(_ field: Field) -> String {
        switch field {
        case .shikimoriAPI:
            return shikimoriXcconfigHost(for: .api) ?? "shikimori.me"
        case .shikimoriOAuth:
            return shikimoriXcconfigHost(for: .oauth) ?? "shikimori.one"
        case .kodikAPI:
            return KodikConfiguration.default.apiHost
        case .kodikReferer:
            return KodikConfiguration.default.refererHost
        }
    }

    func isValid(_ field: Field) -> Bool {
        switch field {
        case .shikimoriAPI:
            return ShikimoriHostsStore.isAcceptableInput(shikimoriAPIDraft)
        case .shikimoriOAuth:
            return ShikimoriHostsStore.isAcceptableInput(shikimoriOAuthDraft)
        case .kodikAPI:
            return KodikHostsStore.isAcceptableInput(kodikAPIDraft)
        case .kodikReferer:
            return KodikHostsStore.isAcceptableInput(kodikRefererDraft)
        }
    }

    /// Persists the draft for `field` if it is valid. Empty draft removes the
    /// override key entirely (returns to the default).
    func commit(_ field: Field) {
        guard isValid(field) else { return }
        switch field {
        case .shikimoriAPI:
            store(shikimoriAPIDraft, forKey: ShikimoriHostsStore.Field.api.defaultsKey, label: "shikimori_api")
        case .shikimoriOAuth:
            store(shikimoriOAuthDraft, forKey: ShikimoriHostsStore.Field.oauth.defaultsKey, label: "shikimori_oauth")
        case .kodikAPI:
            store(kodikAPIDraft, forKey: KodikHostsStore.Keys.api, label: "kodik_api")
        case .kodikReferer:
            store(kodikRefererDraft, forKey: KodikHostsStore.Keys.referer, label: "kodik_referer")
        }
        flashSaved()
    }

    /// Wipes every host override and resets the on-screen drafts.
    /// Does NOT touch credentials, theme, Kodik token or any cache.
    func resetAll() {
        defaults.removeObject(forKey: ShikimoriHostsStore.Field.api.defaultsKey)
        defaults.removeObject(forKey: ShikimoriHostsStore.Field.oauth.defaultsKey)
        defaults.removeObject(forKey: KodikHostsStore.Keys.api)
        defaults.removeObject(forKey: KodikHostsStore.Keys.referer)
        reloadFromDefaults()
        NetworkLogStore.shared.logUIEvent("settings_hosts_reset")
        flashSaved()
    }

    private func store(_ raw: String, forKey key: String, label: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: key)
            NetworkLogStore.shared.logUIEvent("settings_host_cleared field=\(label)")
        } else {
            defaults.set(trimmed, forKey: key)
            NetworkLogStore.shared.logUIEvent("settings_host_saved field=\(label) len=\(trimmed.count)")
        }
    }

    private func flashSaved() {
        savedFlash = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            savedFlash = false
        }
    }

    // MARK: - Bundle helpers

    private func shikimoriXcconfigHost(for field: ShikimoriHostsStore.Field) -> String? {
        // Read raw xcconfig value (no UserDefaults override) so the placeholder
        // always reflects "what the app would use if the user clears the field".
        let key: String
        switch field {
        case .api: key = "ShikimoriBaseURL"
        case .oauth: key = "ShikimoriOAuthBaseURL"
        }
        guard
            let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty,
            let url = URL(string: value),
            let host = url.host
        else { return nil }
        return host
    }
}
