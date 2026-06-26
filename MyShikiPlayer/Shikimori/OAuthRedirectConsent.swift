//
//  OAuthRedirectConsent.swift
//  MyShikiPlayer
//

import Combine
import Foundation

/// User-approved redirect hosts for the credentialed `/oauth/token` POST,
/// persisted in `UserDefaults`. These extend the hard-coded Shikimori mirrors
/// in `OAuthRedirectPolicy` so the app can follow a moved/banned mirror the
/// build didn't ship with — but only after the user explicitly consents.
enum TrustedOAuthHostsStore {
    private static let key = "settings.oauth.trustedRedirectHosts"

    static func hosts(_ defaults: UserDefaults = .standard) -> Set<String> {
        Set((defaults.stringArray(forKey: key) ?? []).map { $0.lowercased() })
    }

    static func contains(_ host: String, _ defaults: UserDefaults = .standard) -> Bool {
        hosts(defaults).contains(host.lowercased())
    }

    static func add(_ host: String, _ defaults: UserDefaults = .standard) {
        var set = hosts(defaults)
        set.insert(host.lowercased())
        defaults.set(Array(set).sorted(), forKey: key)
    }
}

/// Bridges the OAuth redirect delegate (network layer, off-MainActor) to a UI
/// consent prompt. When the token endpoint redirects to an unknown host, the
/// delegate awaits `requestConsent`; the sheet observes `pending` and resolves
/// the continuation via `approve()` / `deny()`. One prompt at a time — token
/// requests are single-flighted upstream, so concurrent prompts shouldn't occur
/// and are denied defensively if they do.
@MainActor
final class OAuthRedirectConsentCoordinator: ObservableObject {
    static let shared = OAuthRedirectConsentCoordinator()

    struct PendingConsent: Identifiable {
        let id = UUID()
        let host: String
        let fromHost: String
    }

    @Published private(set) var pending: PendingConsent?
    private var continuation: CheckedContinuation<Bool, Never>?

    /// Suspends until the user decides. Returns `false` immediately if another
    /// prompt is already in flight.
    func requestConsent(host: String, fromHost: String) async -> Bool {
        guard pending == nil else { return false }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.pending = PendingConsent(host: host, fromHost: fromHost)
        }
    }

    /// User ticked "I understand" and confirmed — trust the host for future
    /// token redirects and resume the suspended request.
    func approve() {
        if let host = pending?.host {
            TrustedOAuthHostsStore.add(host)
        }
        finish(true)
    }

    /// User cancelled or dismissed the sheet — refuse the redirect.
    func deny() {
        finish(false)
    }

    private func finish(_ allow: Bool) {
        pending = nil
        continuation?.resume(returning: allow)
        continuation = nil
    }
}
