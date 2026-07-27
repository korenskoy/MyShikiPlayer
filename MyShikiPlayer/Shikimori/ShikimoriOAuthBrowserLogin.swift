//
//  ShikimoriOAuthBrowserLogin.swift
//  MyShikiPlayer
//

import AppKit
import Foundation

enum ShikimoriOAuthBrowserLoginError: LocalizedError {
    case missingCallbackScheme
    case missingAuthorizationCode
    case stateMismatch
    case userCancelled
    case unableToOpenBrowser
    case callbackTimeout
    case oauthError(String)

    var errorDescription: String? {
        switch self {
        case .missingCallbackScheme:
            return "В ShikimoriRedirectURI нет URL-схемы (ожидается myshikiplayer://…)"
        case .missingAuthorizationCode:
            return "В ответе OAuth нет параметра code"
        case .stateMismatch:
            return "Ответ браузера не прошёл проверку state и был отклонён. Начните вход заново."
        case .userCancelled:
            return "Вход отменён"
        case .unableToOpenBrowser:
            return "Не удалось открыть браузер для OAuth-авторизации"
        case .callbackTimeout:
            return "Не получили ответ от браузера. Проверьте завершение входа и redirect URI."
        case .oauthError(let message):
            return message
        }
    }
}

/// Outcome of matching a browser OAuth callback against the pending sign-in.
enum ShikimoriOAuthCallbackResult: Equatable {
    case code(String)
    case stateMismatch
    case missingCode
    case failure(String)
}

/// OAuth via the browser using a custom URL scheme callback (myshikiplayer://oauth).
@MainActor
enum ShikimoriOAuthBrowserLogin {
    /// Scheme extracted from the redirect URI (e.g. `myshikiplayer` for `myshikiplayer://oauth`).
    nonisolated static func callbackScheme(from redirectURI: String) -> String? {
        guard let url = URL(string: redirectURI), let scheme = url.scheme, !scheme.isEmpty else { return nil }
        return scheme
    }

    nonisolated static func buildAuthorizeURL(
        configuration: ShikimoriConfiguration,
        scopes: [String],
        pkce: OAuthPKCE
    ) throws -> URL {
        let base = configuration.oauthBaseURL.appendingPathComponent("oauth/authorize")
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientId),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: pkce.state),
            URLQueryItem(name: "code_challenge", value: pkce.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: OAuthPKCE.challengeMethod),
        ]
        guard let url = components?.url else { throw ShikimoriAPIError.invalidURL }
        return url
    }

    /// Pure evaluation of a callback URL against the run that started it.
    /// `state` is verified before anything else is read: any app on the
    /// machine can claim the `myshikiplayer://` scheme, so a callback we did
    /// not start must never be able to hand us a code or an error message.
    nonisolated static func evaluateCallback(
        url: URL,
        expectedState: String?
    ) -> ShikimoriOAuthCallbackResult {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let receivedState = items.first { $0.name == "state" }?.value
        guard let expectedState, !expectedState.isEmpty, receivedState == expectedState else {
            return .stateMismatch
        }
        if let failure = items.first(where: { $0.name == "error" })?.value {
            let description = items.first(where: { $0.name == "error_description" })?.value ?? failure
            return .failure(description)
        }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            return .missingCode
        }
        return .code(code)
    }

    /// `state` / `code_challenge` identify the in-flight sign-in, so they are
    /// hidden on top of the store's own masking before anything reaches the
    /// copy-pasteable diagnostics log.
    nonisolated static func maskedOAuthURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return NetworkLogStore.maskedURLString(url)
        }
        let hidden: Set<String> = ["state", "code_challenge", "code_verifier"]
        components.queryItems = components.queryItems?.map { item in
            hidden.contains(item.name.lowercased()) ? URLQueryItem(name: item.name, value: "***") : item
        }
        guard let masked = components.url else { return NetworkLogStore.maskedURLString(url) }
        return NetworkLogStore.maskedURLString(masked)
    }

    /// Default scope covers everything the app actually writes today:
    /// `user_rates` (status / score / episode increments — Library, Progress,
    /// Continue Watching), `topics` (creating / editing topics from Social)
    /// and `comments` (replying inside topic threads). See
    /// `docs/SHIKIMORI_CLIENT_API.md` §131 (scope reference) and §82-91
    /// (write-endpoints that need topics / comments).
    static func openAuthorizePage(
        configuration: ShikimoriConfiguration,
        pkce: OAuthPKCE,
        scopes: [String] = ["user_rates", "topics", "comments"]
    ) throws {
        guard callbackScheme(from: configuration.redirectURI) != nil else {
            throw ShikimoriOAuthBrowserLoginError.missingCallbackScheme
        }
        let authorizeURL = try buildAuthorizeURL(configuration: configuration, scopes: scopes, pkce: pkce)
        NetworkLogStore.shared.logOAuthEvent("open_browser \(maskedOAuthURLString(authorizeURL))")
        guard NSWorkspace.shared.open(authorizeURL) else {
            NetworkLogStore.shared.logOAuthEvent("open_browser_failed")
            throw ShikimoriOAuthBrowserLoginError.unableToOpenBrowser
        }
        NetworkLogStore.shared.logOAuthEvent("open_browser_ok")
    }
}
