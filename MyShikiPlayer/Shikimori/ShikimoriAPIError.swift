//
//  ShikimoriAPIError.swift
//  MyShikiPlayer
//

import Foundation

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
            if let body, !body.isEmpty, let text = String(data: body, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "HTTP \(code): \(text)"
            }
            return "HTTP \(code): пустой ответ."
        case .decoding(let underlying, _):
            return "Не удалось разобрать ответ сервера: \(underlying.localizedDescription)\(decodedBodyPreviewText())"
        case .graphqlErrors(let errors):
            let message = errors.map(\.message).joined(separator: "; ")
            return "GraphQL ошибка: \(message)"
        }
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
