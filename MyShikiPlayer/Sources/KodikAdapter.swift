//
//  KodikAdapter.swift
//  MyShikiPlayer
//

import Foundation

struct KodikAdapter: SourceAdapter {
    let provider: SourceProvider = .kodik
    /// Built per call so the user's host overrides (Settings → "Домены")
    /// take effect on the very next playback without restarting the app.
    /// `KodikConfiguration.current()` is a couple of UserDefaults reads, so
    /// rebuilding the client/resolver here is essentially free compared to
    /// the network round-trips that follow.
    private var client: KodikClient { KodikClient() }
    private var linksResolver: KodikVideoLinksResolver { KodikVideoLinksResolver() }

    func resolve(request: SourceResolutionRequest) async throws -> SourceResolutionResult {
        let preferredTranslationText = request.preferredTranslationId.map { String($0) } ?? "nil"
        await log("resolve_start shikimori_id=\(request.shikimoriId) episode=\(request.episode) preferred_translation=\(preferredTranslationText)")

        let materials = try await loadCatalog(shikimoriId: request.shikimoriId)
        let ordered = orderedMaterials(materials, preferred: request.preferredTranslationId)
        await log("resolve_order preferred_translation=\(preferredTranslationText) total=\(ordered.count)")

        // Build the full DUB-picker list up front — it has zero network cost
        // (data already in catalog) and lets the player surface every studio
        // even before its streams are resolved.
        let studios = ordered.map { material in
            StudioOption(
                provider: provider,
                studioId: material.translation.id,
                studioLabel: material.translation.title
            )
        }

        // Resolve only the first material with an episode link for this episode.
        // The remaining studios stay in `studios` and are resolved on demand
        // via `resolveStudio(...)` when the user actually picks them.
        var lastFatalError: PlayerError?
        for material in ordered {
            guard let episodeLink = material.link(for: request.episode) else {
                await log("resolve_skip translation_id=\(material.translation.id) reason=no_episode_link")
                continue
            }
            do {
                let streams = try await resolveStreams(for: material, episodeLink: episodeLink)
                if streams.isEmpty {
                    await log("resolve_translation_empty translation_id=\(material.translation.id)")
                    continue
                }
                await log(
                    "resolve_ok primary_translation_id=\(material.translation.id)"
                    + " streams=\(streams.count) studios_total=\(studios.count)"
                )
                return SourceResolutionResult(streams: streams, studios: studios)
            } catch let kodikError as KodikSourceError {
                let mapped = Self.mapToPlayerError(kodikError)
                await log(
                    "resolve_translation_fail translation_id=\(material.translation.id)"
                    + " kind=\(Self.diagnosticName(for: kodikError))"
                    + " mapped=\(Self.diagnosticName(for: mapped))"
                )
                // Auth / banned must not be silently swallowed: surface them so
                // the UI can prompt the user for the right action instead of
                // generically saying "no streams".
                switch kodikError {
                case .auth, .banned:
                    throw mapped
                case .transient, .parse, .network:
                    lastFatalError = mapped
                    continue
                }
            } catch {
                await log(
                    "resolve_translation_fail translation_id=\(material.translation.id) error=\(error.localizedDescription)"
                )
                // Unknown error — fall through to noStreamFound after the loop.
                continue
            }
        }

        if let lastFatalError {
            await log("resolve_fail reason=last_provider_error error=\(lastFatalError.localizedDescription)")
            throw lastFatalError
        }

        await log("resolve_fail reason=no_streams")
        throw PlayerError.noStreamFound
    }

    func resolveStudio(
        request: SourceResolutionRequest,
        studioId: Int
    ) async throws -> [SourceStream] {
        await log(
            "resolve_studio_start shikimori_id=\(request.shikimoriId)"
            + " episode=\(request.episode) studio_id=\(studioId)"
        )
        let materials = try await loadCatalog(shikimoriId: request.shikimoriId)
        guard let material = materials.first(where: { $0.translation.id == studioId }) else {
            await log("resolve_studio_fail studio_id=\(studioId) reason=not_in_catalog")
            throw PlayerError.noStreamFound
        }
        guard let episodeLink = material.link(for: request.episode) else {
            await log("resolve_studio_fail studio_id=\(studioId) reason=no_episode_link")
            throw PlayerError.noStreamFound
        }
        do {
            let streams = try await resolveStreams(for: material, episodeLink: episodeLink)
            if streams.isEmpty {
                await log("resolve_studio_fail studio_id=\(studioId) reason=empty_streams")
                throw PlayerError.noStreamFound
            }
            await log("resolve_studio_ok studio_id=\(studioId) streams=\(streams.count)")
            return streams
        } catch let kodikError as KodikSourceError {
            let mapped = Self.mapToPlayerError(kodikError)
            await log(
                "resolve_studio_fail studio_id=\(studioId)"
                + " kind=\(Self.diagnosticName(for: kodikError))"
                + " mapped=\(Self.diagnosticName(for: mapped))"
            )
            throw mapped
        }
    }

    private func loadCatalog(shikimoriId: Int) async throws -> [KodikCatalogEntry] {
        // Token is required only to *refresh* the /search catalog. Episode
        // links from a previously cached catalog still resolve through the
        // public /ftor endpoint without one — so a missing token must NOT
        // block playback when KodikCatalogRepo already has fresh entries.
        if let cached = await KodikCatalogRepo.shared.cachedCatalog(
            shikimoriId: shikimoriId,
            allowStale: true
        ), !cached.isEmpty {
            await log("resolve_catalog_from_cache translations=\(cached.count)")
            return cached
        }
        guard let token = KodikTokenManager.resolveToken() else {
            await log("resolve_fail reason=missing_token")
            // Missing token is an auth-shaped problem ("ask the user to enter
            // it") rather than a generic "source down".
            throw PlayerError.providerAuthFailed("Kodik")
        }
        await log("resolve_token_ok token_len=\(token.count)")
        do {
            let materials = try await KodikCatalogRepo.shared.catalog(
                shikimoriId: shikimoriId,
                token: token,
                client: client
            )
            await log("resolve_catalog translations=\(materials.count)")
            return materials
        } catch let kodikError as KodikSourceError {
            let mapped = Self.mapToPlayerError(kodikError)
            await log(
                "resolve_catalog_fail kind=\(Self.diagnosticName(for: kodikError))"
                + " mapped=\(Self.diagnosticName(for: mapped))"
            )
            throw mapped
        }
    }

    private func orderedMaterials(
        _ materials: [KodikCatalogEntry],
        preferred: Int?
    ) -> [KodikCatalogEntry] {
        guard let preferred else { return materials }
        let match = materials.filter { $0.translation.id == preferred }
        let rest = materials.filter { $0.translation.id != preferred }
        return match + rest
    }

    private func resolveStreams(
        for material: KodikCatalogEntry,
        episodeLink: String
    ) async throws -> [SourceStream] {
        await log("resolve_translation translation_id=\(material.translation.id) title=\(material.translation.title)")
        let links = try await linksResolver.resolve(from: episodeLink)
        let mapped: [SourceStream] = links.compactMap { pair in
            guard let url = URL(string: pair.urlString) else { return nil }
            return SourceStream(
                qualityLabel: "\(pair.quality)p",
                studioLabel: material.translation.title,
                studioId: material.translation.id,
                url: url,
                openingRangeSeconds: pair.openingRangeSeconds,
                endingRangeSeconds: pair.endingRangeSeconds
            )
        }
        await log("resolve_translation_ok translation_id=\(material.translation.id) streams=\(mapped.count)")
        return uniqueStreams(mapped)
    }

    private func uniqueStreams(_ streams: [SourceStream]) -> [SourceStream] {
        var seen = Set<URL>()
        var out: [SourceStream] = []
        for s in streams where !seen.contains(s.url) {
            seen.insert(s.url)
            out.append(s)
        }
        return out
    }

    private func log(_ message: String) async {
        NetworkLogStore.shared.logUIEvent("kodik_adapter \(message)")
    }

    /// Single bridge between the SDK-level `KodikSourceError` taxonomy and the
    /// UI-facing `PlayerError`. Keeping it in one place means new categories
    /// only have to be wired here.
    static func mapToPlayerError(_ error: KodikSourceError) -> PlayerError {
        switch error {
        case .auth:
            return .providerAuthFailed("Kodik")
        case .banned:
            return .providerBlocked("Kodik")
        case .transient(let status):
            // Funnel through the existing streamBuildFailed surface so the
            // current "retry" overlay keeps working without touching the UI;
            // additionally expose the typed transient case for new callers.
            return .providerTransient(provider: "Kodik", status: status)
        case .parse(let message):
            return .streamBuildFailed("Kodik parse: \(message)")
        case .network(let underlying):
            return .streamBuildFailed("Kodik network: \(underlying.localizedDescription)")
        }
    }

    /// Compact diagnostic label for log lines (avoid leaking long messages).
    static func diagnosticName(for error: KodikSourceError) -> String {
        switch error {
        case .auth: return "auth"
        case .banned: return "banned"
        case .transient(let status): return "transient(\(status))"
        case .parse: return "parse"
        case .network: return "network"
        }
    }

    static func diagnosticName(for error: PlayerError) -> String {
        switch error {
        case .noStreamFound: return "noStreamFound"
        case .streamBuildFailed: return "streamBuildFailed"
        case .sourceUnavailable: return "sourceUnavailable"
        case .providerAuthFailed: return "providerAuthFailed"
        case .providerBlocked: return "providerBlocked"
        case .providerTransient(_, let status): return "providerTransient(\(status))"
        }
    }
}
