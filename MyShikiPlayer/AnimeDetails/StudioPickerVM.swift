//
//  StudioPickerVM.swift
//  MyShikiPlayer
//
//  Resolves "which translation should be pre-selected" for the Details
//  screen and persists the user's last pick by studio name (across titles —
//  `translation.id` differs between titles, but the studio title is stable).
//
//  Pure logic + UserDefaults; no @Published state of its own — the owner
//  (AnimeDetailsViewModel) keeps `selectedTranslationId` published so the
//  view does not rebuild because of the split.
//

import Foundation

@MainActor
struct StudioPickerVM {
    /// UserDefaults key for the cross-title studio name memory.
    private static let preferredStudioNameKey = "details.preferredStudioName"

    private var persistedStudioName: String {
        get { UserDefaults.standard.string(forKey: Self.preferredStudioNameKey) ?? "" }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: Self.preferredStudioNameKey) }
    }

    /// Resolves the translation id we should pre-select after a snapshot apply.
    /// Mirrors the original 4-step rule from `AnimeDetailsViewModel`:
    ///   1. Fresh choice from the player session.
    ///   2. Current selection in the VM (after returning from the player).
    ///   3. Persisted studio by name (across titles).
    ///   4. First available.
    func resolvePreferredTranslationId(
        catalogEntries: [KodikCatalogEntry],
        sessionPreferred: Int?,
        currentlySelected: Int?
    ) -> Int? {
        if let sessionPref = sessionPreferred,
           catalogEntries.contains(where: { $0.translation.id == sessionPref }) {
            return sessionPref
        }
        if let current = currentlySelected,
           catalogEntries.contains(where: { $0.translation.id == current }) {
            return current
        }
        let name = persistedStudioName
        if !name.isEmpty,
           let match = catalogEntries.first(where: { $0.translation.title == name }) {
            return match.translation.id
        }
        return catalogEntries.first?.translation.id
    }

    /// Persist the studio name behind the freshly selected translation id, so
    /// the next title opens with the same dub if available.
    func persistStudioName(forTranslationId id: Int?, in catalogEntries: [KodikCatalogEntry]) {
        guard let id,
              let entry = catalogEntries.first(where: { $0.translation.id == id }) else { return }
        let name = entry.translation.title
        guard !name.isEmpty, persistedStudioName != name else { return }
        persistedStudioName = name
        NetworkLogStore.shared.logUIEvent("details_studio_persisted=\(name)")
    }
}
