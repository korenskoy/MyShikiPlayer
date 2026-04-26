//
//  NetworkLogStore.swift
//  MyShikiPlayer
//

import Combine
import Foundation

/// In-memory ring buffer of network and app-level events surfaced in the
/// debug Network Log panel. Lives outside the Shikimori module because it is
/// shared across Shikimori, Kodik, repositories, and player diagnostics.
@MainActor
final class NetworkLogStore: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let line: String
    }

    static let shared = NetworkLogStore()

    /// Mirror of `UserDefaults("settings.networkLogsEnabled")`. End users see
    /// the toggle in Settings → Diagnostics; default `false` so the buffer
    /// stays empty and `previewFromResponseData` skips JSON parsing for the
    /// vast majority of users who never open the panel.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "settings.networkLogsEnabled")
    }

    @Published private(set) var entries: [Entry] = []
    private let timeFormatter: DateFormatter
    private let maxEntries = 500

    private init() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        self.timeFormatter = formatter
    }

    func log(
        method: String,
        url: URL?,
        statusCode: Int?,
        duration: TimeInterval,
        responseBytes: Int?,
        responsePreview: String?,
        errorDescription: String?
    ) {
        guard Self.isEnabled else { return }
        let statusPart = statusCode.map { "\($0)" } ?? "ERR"
        let ms = Int((duration * 1000).rounded())
        let size = responseBytes.map { "\($0)B" } ?? "-"
        let urlText = url?.absoluteString ?? "<no-url>"
        let errorPart = errorDescription.map { " \($0)" } ?? ""
        let previewPart = responsePreview.map { " body=\($0)" } ?? ""
        let line = "\(timeFormatter.string(from: Date())) \(method) \(statusPart) \(ms)ms \(size) \(urlText)\(errorPart)\(previewPart)"

        append(line)
    }

    func clear() {
        entries.removeAll(keepingCapacity: true)
    }

    func exportText() -> String {
        entries.map(\.line).joined(separator: "\n")
    }

    func logOAuthEvent(_ message: String) {
        guard Self.isEnabled else { return }
        append("\(timeFormatter.string(from: Date())) OAUTH \(message)")
    }

    func logAppError(_ message: String) {
        guard Self.isEnabled else { return }
        append("\(timeFormatter.string(from: Date())) APP_ERROR \(message)")
    }

    func logUIEvent(_ message: String) {
        guard Self.isEnabled else { return }
        append("\(timeFormatter.string(from: Date())) UI \(message)")
    }

    private func append(_ line: String) {
        entries.append(Entry(timestamp: Date(), line: line))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    static func maskedURLString(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        let sensitive = Set(["code", "client_secret", "refresh_token", "access_token", "token"])
        components.queryItems = components.queryItems?.map { item in
            guard sensitive.contains(item.name.lowercased()) else { return item }
            return URLQueryItem(name: item.name, value: "***")
        }
        return components.string ?? url.absoluteString
    }

    static func previewFromResponseData(_ data: Data, maxBytes: Int) -> String {
        // Hottest path on every successful network response: JSON parse +
        // sanitize for an entry that nobody will read when logs are off.
        guard isEnabled else { return "" }
        guard !data.isEmpty else { return "\"\"" }
        let prefixData = data.prefix(maxBytes)

        if let json = try? JSONSerialization.jsonObject(with: Data(prefixData)),
           let sanitized = sanitizeJSONObject(json),
           let sanitizedData = try? JSONSerialization.data(withJSONObject: sanitized),
           var text = String(data: sanitizedData, encoding: .utf8) {
            text = text.replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            return "\"\(text)\""
        }

        if var text = String(data: prefixData, encoding: .utf8) {
            text = text
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if data.count > maxBytes {
                text += "…"
            }
            return "\"\(text)\""
        }
        return "<\(prefixData.count) bytes binary>"
    }

    private static func sanitizeJSONObject(_ object: Any) -> Any? {
        let sensitive = Set(["access_token", "refresh_token", "client_secret", "token", "code"])

        if let dict = object as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, value) in dict {
                if sensitive.contains(key.lowercased()) {
                    out[key] = "***"
                } else {
                    out[key] = sanitizeJSONObject(value)
                }
            }
            return out
        }
        if let array = object as? [Any] {
            return array.map { sanitizeJSONObject($0) as Any }
        }
        return object
    }
}
