//
//  KodikVideoLinksResolver.swift
//  MyShikiPlayer
//

import Foundation

// swiftlint:disable type_body_length
struct KodikVideoLinksResolver {
    struct ResolvedLink {
        let quality: String
        let urlString: String
        let openingRangeSeconds: ClosedRange<Double>?
        let endingRangeSeconds: ClosedRange<Double>?
    }

    let session: URLSession
    /// User-overridable Kodik hosts. Read once per resolver instance — and
    /// because resolvers are short-lived (one per resolve flow), each new
    /// flow picks up the latest Settings values automatically.
    let configuration: KodikConfiguration

    init(
        session: URLSession = .shared,
        configuration: KodikConfiguration = .current()
    ) {
        self.session = session
        self.configuration = configuration
    }

    func resolve(from link: String) async throws -> [ResolvedLink] {
        await log("resolve_start input=\(link)")
        if let cached = await KodikResolvedLinksCache.shared.cached(for: link) {
            await log("resolve_cache_hit links=\(cached.count)")
            return cached
        }
        let parsed = try parseKodikLink(link)
        await log("resolve_parsed host=\(parsed.host) type=\(parsed.type) id=\(parsed.id)")
        let normalized = normalizeKodikLink(link)
        await log("resolve_page_request url=\(normalized)")
        let page = try await fetchText(normalized)
        await log("resolve_page_response bytes=\(page.utf8.count) preview=\(preview(page, max: 260))")
        let hasSkipMarker = page.contains("parseSkipButton(") || page.contains("parseSkipButtons(")
        await log("resolve_page_skip_marker present=\(hasSkipMarker)")
        let skipRanges = parseSkipRanges(from: page)
        let openingRange = skipRanges.opening
        let endingRange = skipRanges.ending
        if let openingRange {
            await log("resolve_opening_range start=\(Int(openingRange.lowerBound)) end=\(Int(openingRange.upperBound))")
        } else {
            await log("resolve_opening_range none")
        }
        if let endingRange {
            await log("resolve_ending_range start=\(Int(endingRange.lowerBound)) end=\(Int(endingRange.upperBound))")
        } else {
            await log("resolve_ending_range none")
        }
        let playerSinglePath = firstMatch(in: page, pattern: #"src="(?<link>/assets/js/app\.player_single\.[a-z0-9]+\.js)""#, group: "link")

        var videoInfoEndpoint = "/ftor"
        if let playerSinglePath {
            await log("resolve_player_js path=\(playerSinglePath)")
            let js = try await fetchText("https://\(parsed.host)\(playerSinglePath)")
            if let endpointB64 = firstMatch(in: js, pattern: #"type:"POST",url:atob\("(?<b64str>[^"]+)"\)"#, group: "b64str"),
               let endpointData = Data(base64Encoded: endpointB64),
               let endpoint = String(data: endpointData, encoding: .utf8),
               endpoint.first == "/" {
                videoInfoEndpoint = endpoint
                await log("resolve_endpoint_from_js endpoint=\(endpoint)")
            }
        }

        let links = try await fetchVideoInfoLinks(
            parsed: parsed,
            endpoint: videoInfoEndpoint,
            referer: normalized
        )

        var out: [ResolvedLink] = []
        var skippedByFormat = 0
        var skippedByDecode = 0
        var decodedByStrategy: [String: Int] = [:]
        for (quality, rawSources) in links {
            let srcCandidates = extractSourceCandidates(from: rawSources)
            if srcCandidates.isEmpty {
                skippedByFormat += 1
                await log("resolve_quality_skip quality=\(quality) reason=unsupported_links_shape type=\(type(of: rawSources))")
                continue
            }

            for srcRaw in srcCandidates {
                guard let decoded = decodeSourceURL(from: srcRaw) else {
                    skippedByDecode += 1
                    continue
                }
                decodedByStrategy[decoded.strategy, default: 0] += 1
                out.append(
                    ResolvedLink(
                        quality: quality,
                        urlString: decoded.urlString,
                        openingRangeSeconds: openingRange,
                        endingRangeSeconds: endingRange
                    )
                )
            }
        }

        let order = ["1080", "720", "480", "360", "240"]
        let sorted = out.sorted { lhs, rhs in
            let li = order.firstIndex(of: lhs.quality) ?? Int.max
            let ri = order.firstIndex(of: rhs.quality) ?? Int.max
            return li < ri
        }
        let qualities = Set(sorted.map(\.quality)).sorted().joined(separator: ",")
        let strategySummary = decodedByStrategy
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
        await log("resolve_ok links=\(sorted.count) qualities=[\(qualities)] skipped_format=\(skippedByFormat) skipped_decode=\(skippedByDecode) strategies=[\(strategySummary)]")
        await KodikResolvedLinksCache.shared.store(sorted, for: link)
        return sorted
    }

    /// Issues the `/ftor` (or JS-discovered) POST and decodes the `links`
    /// payload into a typed dictionary. Extracted from `resolve(from:)` so the
    /// outer function fits the project's body-length budget and so the error
    /// classification has a single home.
    private func fetchVideoInfoLinks(
        parsed: ParsedKodikLink,
        endpoint: String,
        referer: String
    ) async throws -> [String: Any] {
        var comps = URLComponents(string: "https://\(parsed.host)\(endpoint)")!
        comps.queryItems = [
            URLQueryItem(name: "type", value: parsed.type),
            URLQueryItem(name: "id", value: parsed.id),
            URLQueryItem(name: "hash", value: parsed.hash)
        ]
        guard let videoInfoURL = comps.url else {
            await log("resolve_fail reason=invalid_video_info_url")
            throw KodikSourceError.parse("invalid video info URL")
        }
        await log("resolve_video_info_request url=\(NetworkLogStore.maskedURLString(videoInfoURL))")

        let request = makeRequest(
            url: videoInfoURL,
            accept: "application/json, text/plain, */*",
            referer: referer
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            await log("resolve_fail reason=transport error=\(error.localizedDescription)")
            throw KodikSourceError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            await log("resolve_fail reason=non_http_response")
            throw KodikSourceError.parse("video info returned non-HTTP response")
        }
        if let classified = KodikSourceError.classify(httpStatus: http.statusCode) {
            await log("resolve_fail reason=video_info_non_2xx status=\(http.statusCode)")
            throw classified
        }
        await log("resolve_video_info_response status=\(http.statusCode) bytes=\(data.count)")
        await log("resolve_video_info_preview body=\(preview(data: data, max: 512))")

        let json: [String: Any]?
        do {
            json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            await log("resolve_fail reason=json_decode error=\(error.localizedDescription)")
            throw KodikSourceError.parse("video info decode failed: \(error.localizedDescription)")
        }
        guard let links = json?["links"] as? [String: Any] else {
            await log("resolve_fail reason=links_missing")
            throw KodikSourceError.parse("video links missing")
        }
        return links
    }

    private func extractSourceCandidates(from rawSources: Any) -> [String] {
        // Known Kodik shapes seen in the wild:
        // - [[{"src": "..."}]]
        // - {"src": "..."} / {"src": ["..."]}
        // - ["..."]
        // - "..."
        if let sources = rawSources as? [[String: Any]] {
            return sources.compactMap { $0["src"] as? String }
        }
        if let source = rawSources as? [String: Any] {
            if let src = source["src"] as? String {
                return [src]
            }
            if let srcList = source["src"] as? [String] {
                return srcList
            }
            return []
        }
        if let srcList = rawSources as? [String] {
            return srcList
        }
        if let src = rawSources as? String {
            return [src]
        }
        return []
    }

    private func decodeSourceURL(from srcRaw: String) -> (urlString: String, strategy: String)? {
        if let normalized = normalizeDirectURL(srcRaw) {
            return (normalized, "direct")
        }

        let candidates: [(String, String)] = [
            (srcRaw, "base64"),
            (normalizeBase64(srcRaw), "base64_urlsafe"),
            (rotateLettersBy18(srcRaw), "rot18_base64"),
            (normalizeBase64(rotateLettersBy18(srcRaw)), "rot18_base64_urlsafe")
        ]

        for (candidate, strategy) in candidates {
            guard let decoded = decodeBase64String(candidate),
                  let normalized = normalizeDirectURL(decoded) else {
                continue
            }
            return (normalized, strategy)
        }

        return nil
    }

    private func decodeBase64String(_ value: String) -> String? {
        guard let data = Data(base64Encoded: value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func normalizeBase64(_ value: String) -> String {
        var output = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = output.count % 4
        if remainder != 0 {
            output += String(repeating: "=", count: 4 - remainder)
        }
        return output
    }

    private func normalizeDirectURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("//") {
            return "https:\(trimmed)"
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        if trimmed.contains(".m3u8") || trimmed.contains(".mp4") || trimmed.contains("/") {
            return "https://\(trimmed)"
        }
        return nil
    }

    /// Parses Kodik's `parseSkipButtons("00:00-01:30,21:00-22:30","...")`
    /// payload. With two pairs, the first is the opening and the second is
    /// the ending; extra pairs are ignored. With a single pair, we don't know
    /// the episode duration here, so we use a positional heuristic: a range
    /// that starts past `singleRangeOpeningCutoffSeconds` (5 min) cannot be
    /// an opening — anime openings always sit at the very start of the
    /// episode — so it is classified as the ending. This restores the
    /// historical behaviour for shows that only mark the ending.
    /// Pairs with `start >= end` are dropped as invalid.
    private func parseSkipRanges(
        from page: String
    ) -> (opening: ClosedRange<Double>?, ending: ClosedRange<Double>?) {
        guard let data = firstMatch(
            in: page,
            pattern: #"parseSkipButtons?\("(?<data>[^"]+)"\s*,\s*"(?<type>[^"]+)"\)"#,
            group: "data"
        ) else {
            return (nil, nil)
        }
        let pairs = data
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .prefix(2)
        let parsed: [ClosedRange<Double>] = pairs.compactMap { token in
            let parts = token.split(separator: "-")
            guard parts.count == 2,
                  let start = parseTimeToken(String(parts[0])),
                  let end = parseTimeToken(String(parts[1])),
                  end > start else {
                return nil
            }
            return start...end
        }
        if parsed.count >= 2 {
            return (parsed[0], parsed[1])
        }
        guard let only = parsed.first else {
            return (nil, nil)
        }
        if only.lowerBound >= Self.singleRangeOpeningCutoffSeconds {
            return (nil, only)
        }
        return (only, nil)
    }

    /// Anime openings start at 0:00 (sometimes after a brief cold-open of
    /// well under a minute) and never extend past 5 minutes. A single-pair
    /// payload starting later than this cutoff is therefore an ending.
    private static let singleRangeOpeningCutoffSeconds: Double = 300

    private func parseTimeToken(_ value: String) -> Double? {
        let token = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }

        if !token.contains(":") {
            return Double(token)
        }

        let chunks = token.split(separator: ":").map(String.init)
        guard chunks.count == 2 || chunks.count == 3 else { return nil }
        let numbers = chunks.compactMap { Double($0) }
        guard numbers.count == chunks.count else { return nil }

        if numbers.count == 2 {
            let minutes = numbers[0]
            let seconds = numbers[1]
            return (minutes * 60) + seconds
        }

        let hours = numbers[0]
        let minutes = numbers[1]
        let seconds = numbers[2]
        return (hours * 3600) + (minutes * 60) + seconds
    }

    private struct ParsedKodikLink {
        let host: String
        let type: String
        let id: String
        let hash: String
    }

    private func normalizeKodikLink(_ input: String) -> String {
        if input.hasPrefix("//") { return "https:\(input)" }
        if input.hasPrefix("http://") || input.hasPrefix("https://") { return input }
        return "https://kodikplayer.com\(input.hasPrefix("/") ? "" : "/")\(input)"
    }

    private func parseKodikLink(_ link: String) throws -> ParsedKodikLink {
        let normalized = normalizeKodikLink(link)
        let regex = try NSRegularExpression(
            pattern: #"^(?:https?:)?\/\/(?<host>[a-z0-9\.-]+\.[a-z]+)\/(?<type>[a-z]+)\/(?<id>\d+)\/(?<hash>[0-9a-z]+)\/(?<quality>\d+p)(?:.*)$"#,
            options: [.caseInsensitive]
        )
        let ns = normalized as NSString
        guard let m = regex.firstMatch(in: normalized, range: NSRange(location: 0, length: ns.length)) else {
            throw KodikSourceError.parse("invalid kodik player link")
        }

        func g(_ name: String) -> String {
            let range = m.range(withName: name)
            if range.location == NSNotFound { return "" }
            return ns.substring(with: range)
        }

        return ParsedKodikLink(host: g("host"), type: g("type"), id: g("id"), hash: g("hash"))
    }

    private func fetchText(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw KodikSourceError.parse("invalid URL \(urlString)")
        }
        let request = makeRequest(
            url: url,
            accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            referer: configuration.refererURLString
        )
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw KodikSourceError.network(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw KodikSourceError.parse("non-HTTP response \(urlString)")
        }
        if let classified = KodikSourceError.classify(httpStatus: http.statusCode) {
            throw classified
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw KodikSourceError.parse("non-utf8 response \(urlString)")
        }
        return text
    }

    private func makeRequest(url: URL, accept: String, referer: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:149.0) Gecko/20100101 Firefox/149.0",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        return request
    }

    private func firstMatch(in text: String, pattern: String, group: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = text as NSString
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        let range = m.range(withName: group)
        guard range.location != NSNotFound else { return nil }
        return ns.substring(with: range)
    }

    private func rotateLettersBy18(_ text: String) -> String {
        let aUpper = UnicodeScalar("A").value
        let zUpper = UnicodeScalar("Z").value
        let aLower = UnicodeScalar("a").value
        let zLower = UnicodeScalar("z").value

        let scalars = text.unicodeScalars.map { scalar -> UnicodeScalar in
            let v = scalar.value
            if (aUpper...zUpper).contains(v) {
                let shifted = ((v - aUpper + 18) % 26) + aUpper
                return UnicodeScalar(shifted) ?? scalar
            }
            if (aLower...zLower).contains(v) {
                let shifted = ((v - aLower + 18) % 26) + aLower
                return UnicodeScalar(shifted) ?? scalar
            }
            return scalar
        }
        return String(String.UnicodeScalarView(scalars))
    }

    private func log(_ message: String) async {
        await MainActor.run {
            NetworkLogStore.shared.logUIEvent("kodik_resolver \(message)")
        }
    }

    private func preview(_ text: String, max: Int) -> String {
        let trimmed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= max { return "\"\(trimmed)\"" }
        let prefix = String(trimmed.prefix(max))
        return "\"\(prefix)…\""
    }

    private func preview(data: Data, max: Int) -> String {
        guard !data.isEmpty else { return "\"\"" }
        let prefixData = data.prefix(max)
        if let text = String(data: prefixData, encoding: .utf8) {
            return preview(text, max: max)
        }
        return "<binary \(prefixData.count)B>"
    }
}
// swiftlint:enable type_body_length
