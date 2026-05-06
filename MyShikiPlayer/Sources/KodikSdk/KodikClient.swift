//
//  KodikClient.swift
//  MyShikiPlayer
//

import Foundation

struct KodikClient {
    let session: URLSession
    /// `KodikConfiguration.current()` by default — read at init so each
    /// freshly-constructed client picks up the latest user-overridden hosts.
    /// All callers in production build short-lived clients (one per request
    /// flow), so there is no long-lived stale-config hazard.
    let configuration: KodikConfiguration

    init(
        session: URLSession = .shared,
        configuration: KodikConfiguration = .current()
    ) {
        self.session = session
        self.configuration = configuration
    }

    func loadCatalog(shikimoriId: Int, token: String) async throws -> [KodikCatalogEntry] {
        await log("catalog_start shikimori_id=\(shikimoriId) token_present=true token_len=\(token.count)")
        guard var comps = URLComponents(string: "\(configuration.scheme)://\(configuration.apiHost)/search") else {
            await log("catalog_fail reason=invalid_search_url_components")
            throw KodikSourceError.parse("invalid kodik search URL components")
        }
        comps.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "shikimori_id", value: String(shikimoriId)),
            URLQueryItem(name: "with_seasons", value: "true"),
            URLQueryItem(name: "with_episodes", value: "true"),
            URLQueryItem(name: "with_episodes_data", value: "true"),
            URLQueryItem(name: "limit", value: "100")
        ]

        guard let url = comps.url else {
            await log("catalog_fail reason=invalid_search_url")
            // Local input bug (URLComponents could not build a URL) — model as
            // a parse-style failure so callers do not retry it forever.
            throw KodikSourceError.parse("invalid kodik search URL")
        }
        await log("catalog_request url=\(NetworkLogStore.maskedURLString(url))")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Transport failure (DNS, TLS, offline). MUST NOT clear the Kodik
            // token — the caller decides whether to retry / show "no network".
            await log("catalog_fail reason=transport error=\(error.localizedDescription)")
            throw KodikSourceError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            await log("catalog_fail reason=non_http_response")
            throw KodikSourceError.parse("kodik search returned non-HTTP response")
        }

        if let classified = KodikSourceError.classify(httpStatus: http.statusCode) {
            await log("catalog_fail reason=non_2xx status=\(http.statusCode)")
            throw classified
        }

        await log("catalog_response status=\(http.statusCode) bytes=\(data.count)")

        do {
            let responseBody = try JSONDecoder().decode(KodikSearchResponse.self, from: data)
            let entries = responseBody.results.compactMap(Self.makeCatalogEntry)
            await log("catalog_ok results=\(responseBody.results.count) entries=\(entries.count)")
            return entries
        } catch {
            await log("catalog_fail reason=decode error=\(error.localizedDescription)")
            throw KodikSourceError.parse("decode failed: \(error.localizedDescription)")
        }
    }

    static func makeCatalogEntry(from material: KodikMaterial) -> KodikCatalogEntry? {
        guard let translationId = material.translation?.id else { return nil }

        // If the whole material is region-blocked, skip the studio entirely;
        // otherwise the UI would offer it and the resolver would fall into noStreamFound.
        if case .all = material.blockedSeasons {
            return nil
        }

        let title = material.translation?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let kindRaw = material.translation?.type?.lowercased()
        let translation = KodikTranslation(
            id: translationId,
            title: title?.isEmpty == false ? title! : "Перевод \(translationId)",
            kind: kindRaw.flatMap(KodikTranslationKind.init(rawValue:))
        )

        var episodeMap: [Int: String] = [:]

        // Per the docs, episodes live inside seasons (with_seasons=true).
        // The flat material.episodes is kept as a fallback for single-season
        // titles and older API responses.
        if let seasons = material.seasons {
            for (seasonKey, season) in seasons {
                guard let seasonEpisodes = season.episodes else { continue }
                let seasonBlock = blockedValue(for: seasonKey, in: material.blockedSeasons)
                if case .all = seasonBlock { continue }
                let blockedEpisodes: Set<String> = {
                    if case .episodes(let set) = seasonBlock { return set }
                    return []
                }()
                for (key, payload) in seasonEpisodes {
                    if blockedEpisodes.contains(key) { continue }
                    guard let number = Int(key), let link = payload.link else { continue }
                    if episodeMap[number] == nil {
                        episodeMap[number] = link
                    }
                }
            }
        }

        if let episodes = material.episodes {
            for (key, payload) in episodes {
                guard let number = Int(key), let link = payload.link else { continue }
                if episodeMap[number] == nil {
                    episodeMap[number] = link
                }
            }
        }

        return KodikCatalogEntry(translation: translation, episodes: episodeMap, fallbackLink: material.link)
    }

    private static func blockedValue(
        for seasonKey: String,
        in blocked: KodikBlockedSeasons?
    ) -> KodikBlockedSeasons.SeasonValue? {
        guard case .map(let map) = blocked else { return nil }
        return map[seasonKey]
    }

    /// Stays `async` so existing `await log(...)` callsites compile unchanged.
    /// `logUIEvent` is now nonisolated and self-gates on `isEnabled`, so no
    /// MainActor hop is paid when diagnostics are off.
    private func log(_ message: String) async {
        NetworkLogStore.shared.logUIEvent("kodik_client \(message)")
    }
}
