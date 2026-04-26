//
//  ShikimoriAuthController.swift
//  MyShikiPlayer
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class ShikimoriAuthController: ObservableObject {
    @Published private(set) var configuration: ShikimoriConfiguration?
    @Published private(set) var isConfigured: Bool = false
    @Published private(set) var isLoggedIn: Bool = false
    @Published private(set) var profile: CurrentUser?
    @Published private(set) var isBusy: Bool = false
    @Published private(set) var isAuthorizing: Bool = false
    @Published private(set) var isRestoringSession: Bool = true
    /// Set when refresh fails or the refresh token disappears. UI should ask
    /// the user to log in again. The Keychain entry is intentionally LEFT
    /// IN PLACE — only an explicit `signOut()` clears it. See
    /// `feedback_player_resilience` and PLAN-redesign §0.1 / §0.2.
    @Published private(set) var requiresReauth: Bool = false
    @Published var alertMessage: String?

    private let keychain = ShikimoriOAuthCredentialStore()
    private var oauthCodeContinuation: CheckedContinuation<String, Error>?
    private var didTryRestoreSession = false

    init() {
        // `fromMainBundle()` consults `ShikimoriHostsStore` overrides, so
        // every refresh of `configuration` automatically picks up host changes
        // the user just typed in Settings (no relaunch required for the next
        // sign-in / restoreSession / signOut transition).
        configuration = ShikimoriConfiguration.fromMainBundle()
        isConfigured = configuration.map { !$0.clientId.isEmpty && !$0.clientSecret.isEmpty } ?? false
    }

    /// Loads the token from Keychain; refreshes and runs whoami if needed.
    /// Never wipes the Keychain on failure — a network blip, a banned host or
    /// an expired access token must not erase the user's session silently.
    /// On unrecoverable auth failures (401 from refresh / whoami, or a
    /// missing refresh token) we surface `requiresReauth` and let the user
    /// re-trigger OAuth manually.
    func restoreSession() async {
        guard !didTryRestoreSession else { return }
        didTryRestoreSession = true
        isRestoringSession = true
        defer { isRestoringSession = false }
        guard var config = configuration, isConfigured else { return }
        do {
            guard var stored = try keychain.load() else {
                isLoggedIn = false
                profile = nil
                return
            }
            if shouldRefresh(stored) {
                guard let refresh = stored.refreshToken, !refresh.isEmpty else {
                    // No refresh token → cannot extend the session, but the
                    // access token may still work for read-only calls. Keep
                    // the keychain intact and ask for re-auth.
                    NetworkLogStore.shared.logOAuthEvent("restore_no_refresh_token requires_reauth")
                    markRequiresReauth(reason: "no_refresh_token")
                    return
                }
                let tokenClient = OAuthTokenClient(configuration: config)
                do {
                    let response = try await tokenClient.refresh(refresh)
                    stored = OAuthCredential(response: response)
                    try keychain.save(stored)
                } catch let apiError as ShikimoriAPIError where Self.isAuthRejection(apiError) {
                    // 401/403 from /oauth/token means the refresh token is
                    // dead. Don't trash the keychain — the user might want to
                    // copy it for diagnostics; explicit signOut() is the only
                    // wipe path.
                    NetworkLogStore.shared.logOAuthEvent(
                        "restore_refresh_rejected requires_reauth err=\(apiError.localizedDescription)"
                    )
                    markRequiresReauth(reason: "refresh_rejected")
                    return
                }
            }
            config = config.withAccessToken(stored.accessToken)
            configuration = config
            let client = ShikimoriGraphQLClient(configuration: config)
            do {
                profile = try await client.currentUser()
                isLoggedIn = true
                requiresReauth = false
            } catch let apiError as ShikimoriAPIError where Self.isAuthRejection(apiError) {
                // whoami says "unauthorized" — credentials are stale even
                // though refresh succeeded (or wasn't needed). Same policy:
                // keep the keychain, surface a re-auth banner.
                NetworkLogStore.shared.logOAuthEvent(
                    "restore_whoami_rejected requires_reauth err=\(apiError.localizedDescription)"
                )
                markRequiresReauth(reason: "whoami_rejected")
            }
        } catch {
            // Network blip / decoding glitch / keychain read failure — these
            // are NOT auth-level rejections. Keep the session, just surface
            // the message; restoreSession() will be retried next launch.
            alertMessage = error.localizedDescription
            isLoggedIn = false
            profile = nil
            configuration = ShikimoriConfiguration.fromMainBundle()
        }
    }

    /// Centralised "session is stale" entry-point. Idempotent: the cache wipe
    /// runs only on the leading edge so repeated 401s don't churn disk.
    private func markRequiresReauth(reason: String) {
        let wasAlreadyMarked = requiresReauth
        requiresReauth = true
        isLoggedIn = false
        profile = nil
        if !wasAlreadyMarked {
            PersonalCacheCleaner.purge(reason: "requires_reauth/\(reason)")
        }
    }

    /// 401 / 403 — credentials rejected. Used to differentiate auth failures
    /// from transient errors that must NOT trigger a session reset.
    private static func isAuthRejection(_ error: ShikimoriAPIError) -> Bool {
        if case .httpStatus(let code, _) = error, code == 401 || code == 403 {
            return true
        }
        return false
    }

    func signIn() async {
        guard var config = configuration, isConfigured else {
            alertMessage = "Заполните OAuth в Configuration/Secrets.xcconfig и пересоберите приложение."
            return
        }
        // If previous flow is somehow still pending, restart from a clean state.
        if oauthCodeContinuation != nil {
            cancelPendingSignIn()
        }
        isAuthorizing = true
        isBusy = true
        defer {
            isBusy = false
            isAuthorizing = false
        }
        do {
            NetworkLogStore.shared.logOAuthEvent("sign_in_started")
            try ShikimoriOAuthBrowserLogin.openAuthorizePage(configuration: config)
            let code = try await waitForOAuthCallbackCode()
            NetworkLogStore.shared.logOAuthEvent("callback_code_received")
            let response = try await OAuthTokenClient(configuration: config).exchangeAuthorizationCode(code)
            let newCredential = OAuthCredential(response: response)
            try keychain.save(newCredential)
            config = config.withAccessToken(newCredential.accessToken)
            configuration = config
            let client = ShikimoriGraphQLClient(configuration: config)
            profile = try await client.currentUser()
            isLoggedIn = true
            requiresReauth = false
            alertMessage = nil
            NetworkLogStore.shared.logOAuthEvent("sign_in_success")
        } catch let loginError as ShikimoriOAuthBrowserLoginError {
            NetworkLogStore.shared.logOAuthEvent("sign_in_failed \(loginError.localizedDescription)")
            alertMessage = loginError.localizedDescription
        } catch {
            NetworkLogStore.shared.logOAuthEvent("sign_in_failed \(error.localizedDescription)")
            alertMessage = error.localizedDescription
        }
    }

    /// Explicit user-initiated sign-out — the ONLY path that wipes the
    /// keychain. Also drops every personal Shikimori cache so the next user
    /// (or the same user re-logging-in) starts from a clean slate.
    func signOut() {
        do {
            try keychain.clear()
        } catch {
            alertMessage = error.localizedDescription
        }
        isLoggedIn = false
        profile = nil
        requiresReauth = false
        configuration = ShikimoriConfiguration.fromMainBundle()
        isConfigured = configuration.map { !$0.clientId.isEmpty && !$0.clientSecret.isEmpty } ?? false
        PersonalCacheCleaner.purge(reason: "sign_out")
        NetworkLogStore.shared.logOAuthEvent("sign_out")
    }

    private func shouldRefresh(_ cred: OAuthCredential) -> Bool {
        guard let expires = cred.expiresAt else { return false }
        return expires.timeIntervalSinceNow < 120
    }

    func handleOAuthCallback(_ callbackURL: URL) {
        guard let pending = oauthCodeContinuation else { return }
        oauthCodeContinuation = nil
        NetworkLogStore.shared.logOAuthEvent("callback_received \(NetworkLogStore.maskedURLString(callbackURL))")

        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            let desc = items.first(where: { $0.name == "error_description" })?.value ?? err
            pending.resume(throwing: ShikimoriOAuthBrowserLoginError.oauthError(desc))
            return
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            pending.resume(throwing: ShikimoriOAuthBrowserLoginError.missingAuthorizationCode)
            return
        }
        pending.resume(returning: code)
    }

    private func waitForOAuthCallbackCode(timeoutSeconds: TimeInterval = 180) async throws -> String {
        let timeoutNanos = UInt64(timeoutSeconds * 1_000_000_000)
        return try await withCheckedThrowingContinuation { continuation in
            oauthCodeContinuation = continuation
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: timeoutNanos)
                guard let pending = oauthCodeContinuation else { return }
                oauthCodeContinuation = nil
                pending.resume(throwing: ShikimoriOAuthBrowserLoginError.callbackTimeout)
            }
        }
    }

    func cancelPendingSignIn() {
        guard let pending = oauthCodeContinuation else { return }
        oauthCodeContinuation = nil
        NetworkLogStore.shared.logOAuthEvent("sign_in_cancelled")
        pending.resume(throwing: ShikimoriOAuthBrowserLoginError.userCancelled)
    }
}
