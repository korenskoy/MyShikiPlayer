//
//  ShikimoriOAuthBrowserLogin.swift
//  MyShikiPlayer
//

import AppKit
import Foundation

enum ShikimoriOAuthBrowserLoginError: LocalizedError {
    case missingCallbackScheme
    case missingAuthorizationCode
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

/// OAuth via the browser using a custom URL scheme callback (myshikiplayer://oauth).
@MainActor
enum ShikimoriOAuthBrowserLogin {
    /// Scheme extracted from the redirect URI (e.g. `myshikiplayer` for `myshikiplayer://oauth`).
    static func callbackScheme(from redirectURI: String) -> String? {
        guard let url = URL(string: redirectURI), let scheme = url.scheme, !scheme.isEmpty else { return nil }
        return scheme
    }

    static func buildAuthorizeURL(configuration: ShikimoriConfiguration, scopes: [String]) throws -> URL {
        let base = configuration.oauthBaseURL.appendingPathComponent("oauth/authorize")
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientId),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
        ]
        guard let url = components?.url else { throw ShikimoriAPIError.invalidURL }
        return url
    }
    
    /// Default scope covers everything the app actually writes today:
    /// `user_rates` (status / score / episode increments — Library, Progress,
    /// Continue Watching), `topics` (creating / editing topics from Social)
    /// and `comments` (replying inside topic threads). See
    /// `docs/SHIKIMORI_CLIENT_API.md` §131 (scope reference) and §82-91
    /// (write-endpoints that need topics / comments).
    static func openAuthorizePage(
        configuration: ShikimoriConfiguration,
        scopes: [String] = ["user_rates", "topics", "comments"]
    ) throws {
        guard callbackScheme(from: configuration.redirectURI) != nil else {
            throw ShikimoriOAuthBrowserLoginError.missingCallbackScheme
        }
        let authorizeURL = try buildAuthorizeURL(configuration: configuration, scopes: scopes)
        NetworkLogStore.shared.logOAuthEvent("open_browser \(NetworkLogStore.maskedURLString(authorizeURL))")
        guard NSWorkspace.shared.open(authorizeURL) else {
            NetworkLogStore.shared.logOAuthEvent("open_browser_failed")
            throw ShikimoriOAuthBrowserLoginError.unableToOpenBrowser
        }
        NetworkLogStore.shared.logOAuthEvent("open_browser_ok")
    }
}
