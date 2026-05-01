//
//  ShikimoriAPIError.swift
//  MyShikiPlayer
//

import Foundation
import SwiftSoup

struct GraphQLErrorMessage: Codable, Sendable, Equatable {
    let message: String
}

enum ShikimoriAPIError: Error, Sendable {
    case invalidURL
    case invalidResponse
    case httpStatus(code: Int, body: Data?)
    case decoding(underlying: Error, body: Data?)
    case graphqlErrors([GraphQLErrorMessage])
}

extension ShikimoriAPIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Некорректный URL запроса."
        case .invalidResponse:
            return "Сервер вернул некорректный ответ."
        case .httpStatus(let code, let body):
            return Self.humanReadable(httpStatusCode: code, body: body)
        case .decoding(let underlying, _):
            return "Не удалось разобрать ответ сервера: \(underlying.localizedDescription)\(decodedBodyPreviewText())"
        case .graphqlErrors(let errors):
            let message = errors.map(\.message).joined(separator: "; ")
            return "GraphQL ошибка: \(message)"
        }
    }

    /// Builds a UI-friendly message for an HTTP failure: a localised reason
    /// (e.g. "Сервер временно недоступен.") plus the HTTP code, optionally
    /// suffixed with a one-line body excerpt. Shikimori's 5xx responses are
    /// full HTML pages — we run them through SwiftSoup and pull just the
    /// most informative line so the alert never shows raw markup.
    static func humanReadable(httpStatusCode code: Int, body: Data?) -> String {
        let title = statusTitle(for: code)
        let codeSuffix = " (HTTP \(code))"
        guard let snippet = bodySnippet(from: body),
              !snippet.isEmpty,
              !snippetDuplicatesTitle(snippet, title: title) else {
            return title + codeSuffix
        }
        return "\(title) \(snippet)\(codeSuffix)"
    }

    private static func statusTitle(for code: Int) -> String {
        switch code {
        case 400: return "Некорректный запрос."
        case 401: return "Сессия больше не действует."
        case 403: return "Доступ запрещён."
        case 404: return "Запрашиваемая страница не найдена."
        case 408: return "Сервер слишком долго отвечал."
        case 409: return "Конфликт состояния на сервере."
        case 422: return "Сервер не принял данные запроса."
        case 429: return "Слишком много запросов, попробуй позже."
        case 500: return "Внутренняя ошибка сервера."
        case 502: return "Сервер временно недоступен."
        case 503: return "Сервер на обслуживании."
        case 504: return "Сервер не отвечает."
        default:
            if (500..<600).contains(code) { return "Сервер вернул ошибку." }
            if (400..<500).contains(code) { return "Запрос отклонён сервером." }
            return "Сервер вернул неожиданный статус."
        }
    }

    /// Extracts a short, plain-text excerpt from a response body. Recognises
    /// HTML (via SwiftSoup — picks <h1>, then <title>, falls back to body
    /// text) and plain text; returns nil for empty / binary payloads. The
    /// excerpt is collapsed to a single line and hard-capped so the alert
    /// never spills across the screen.
    private static func bodySnippet(from data: Data?) -> String? {
        guard let data, !data.isEmpty,
              let raw = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let candidate: String
        if looksLikeHTML(trimmed),
           let extracted = extractFromHTML(trimmed) {
            candidate = extracted
        } else {
            candidate = trimmed
        }

        return clipForAlert(candidate)
    }

    private static func looksLikeHTML(_ text: String) -> Bool {
        let head = text.prefix(64).lowercased()
        return head.contains("<!doctype") || head.contains("<html") || head.contains("<head")
    }

    /// HTML extraction order: <h1> (Shikimori 5xx pages put the user-facing
    /// reason here, e.g. "Сервер временно недоступен"), then <title>, then
    /// the visible body text. We deliberately ignore <p> follow-ups like
    /// "Попробуй перезагрузить страницу" — those suggest user actions that
    /// don't apply inside the app.
    private static func extractFromHTML(_ html: String) -> String? {
        guard let doc = try? SwiftSoup.parseBodyFragment(html) else { return nil }
        if let h1 = try? doc.select("h1").first(),
           let text = (try? h1.text())?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        if let title = try? doc.title() {
            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedTitle.isEmpty { return trimmedTitle }
        }
        if let body = doc.body(),
           let text = (try? body.text())?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        return nil
    }

    private static func clipForAlert(_ text: String) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let limit = 200
        guard collapsed.count > limit else { return collapsed }
        return collapsed.prefix(limit) + "…"
    }

    /// True when the body excerpt repeats what the localised status title
    /// already says (case-insensitive, ignoring trailing punctuation).
    /// Avoids "Сервер временно недоступен. Сервер временно недоступен (HTTP 502)".
    private static func snippetDuplicatesTitle(_ snippet: String, title: String) -> Bool {
        let normalize: (String) -> String = { text in
            text.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        }
        let s = normalize(snippet)
        let t = normalize(title)
        guard !s.isEmpty, !t.isEmpty else { return false }
        return s == t || s.contains(t) || t.contains(s)
    }

    private func decodedBodyPreviewText() -> String {
        guard case .decoding(_, let body) = self,
              let body,
              !body.isEmpty else { return "" }

        let preview = body.prefix(512)
        if let text = String(data: preview, encoding: .utf8)?
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return " | body: \(text)"
        }
        return " | body: <\(preview.count) bytes binary>"
    }
}
