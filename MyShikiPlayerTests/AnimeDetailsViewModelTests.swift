//
//  AnimeDetailsViewModelTests.swift
//  MyShikiPlayerTests
//

import XCTest
@testable import MyShikiPlayer

/// Covers the public surface of `AnimeDetailsViewModel`:
/// - snapshot → published state mapping (`load()`)
/// - SWR fallback when refresh fails after a cached render
/// - derived UI properties (title, episode count, posters, trailers).
///
/// Network mutation paths (`setStatus`, `toggleFavorite`, `markEpisodeWatched`)
/// are exercised by `ShikimoriAPITests` against `ShikimoriRESTClient` directly;
/// duplicating that here would only retest URLProtocol plumbing.
@MainActor
final class AnimeDetailsViewModelTests: XCTestCase {

    // MARK: - load()

    func testLoadAppliesSnapshotToPublishedState() async {
        let repo = StubAnimeDetailsRepository()
        let snapshot = makeSnapshot(
            detail: makeDetail(id: 42, name: "Cowboy Bebop", russian: "Ковбой Бибоп"),
            catalog: [makeCatalogEntry(translationId: 7, episodes: [1, 2, 3])],
            related: [makeListItem(id: 100, name: "Lain")]
        )
        repo.snapshotResult = .success(snapshot)
        let viewModel = makeViewModel(repository: repo, shikimoriId: 42)

        await viewModel.load()

        XCTAssertEqual(viewModel.detail?.id, 42)
        XCTAssertEqual(viewModel.detail?.russian, "Ковбой Бибоп")
        XCTAssertEqual(viewModel.catalogEntries.count, 1)
        XCTAssertEqual(viewModel.related.first?.id, 100)
        XCTAssertEqual(viewModel.selectedTranslationId, 7)
        guard case .content = viewModel.state else {
            return XCTFail("Expected .content after successful load, got \(viewModel.state)")
        }
    }

    func testLoadAppliesUserRateFromDetail() async {
        let repo = StubAnimeDetailsRepository()
        repo.snapshotResult = .success(
            makeSnapshot(
                detail: makeDetail(
                    favoured: true,
                    userRate: UserRateREST(id: 99, score: 8, status: "watching", episodes: 5, rewatches: 0)
                )
            )
        )
        let viewModel = makeViewModel(repository: repo)

        await viewModel.load()

        XCTAssertEqual(viewModel.userRateId, 99)
        XCTAssertEqual(viewModel.userScore, 8)
        XCTAssertEqual(viewModel.userStatus, "watching")
        XCTAssertEqual(viewModel.userEpisodesWatched, 5)
        XCTAssertTrue(viewModel.isFavorite)
    }

    func testLoadClearsUserRateWhenAbsent() async {
        let repo = StubAnimeDetailsRepository()
        repo.snapshotResult = .success(makeSnapshot(detail: makeDetail(userRate: nil)))
        let viewModel = makeViewModel(repository: repo)

        await viewModel.load()

        XCTAssertNil(viewModel.userRateId)
        XCTAssertNil(viewModel.userStatus)
        XCTAssertNil(viewModel.userScore)
        XCTAssertEqual(viewModel.userEpisodesWatched, 0)
    }

    func testLoadKeepsStaleSnapshotWhenRefreshFails() async {
        let repo = StubAnimeDetailsRepository()
        repo.cached = makeSnapshot(detail: makeDetail(id: 7, russian: "Кэш"))
        repo.snapshotResult = .failure(StubError.unreachable)
        let viewModel = makeViewModel(repository: repo, shikimoriId: 7)

        await viewModel.load()

        // Stale data wins over the refresh error — UI shouldn't blank out.
        XCTAssertEqual(viewModel.detail?.id, 7)
        guard case .content = viewModel.state else {
            return XCTFail("Expected .content while a stale snapshot is visible, got \(viewModel.state)")
        }
    }

    func testLoadShowsErrorWhenNoCachedSnapshotAndRefreshFails() async {
        let repo = StubAnimeDetailsRepository()
        repo.snapshotResult = .failure(StubError.unreachable)
        let viewModel = makeViewModel(repository: repo)

        await viewModel.load()

        guard case .error = viewModel.state else {
            return XCTFail("Expected .error when nothing is loadable, got \(viewModel.state)")
        }
        XCTAssertNil(viewModel.detail)
    }

    // MARK: - Derived state

    func testTitlePrefersRussianWhenPresent() async {
        let viewModel = await loaded(detail: makeDetail(name: "Bleach", russian: "Блич"))
        XCTAssertEqual(viewModel.title, "Блич")
    }

    func testTitleFallsBackToNameWhenRussianBlank() async {
        let viewModel = await loaded(detail: makeDetail(name: "Bleach", russian: ""))
        XCTAssertEqual(viewModel.title, "Bleach")
    }

    func testTitleFallsBackToDashWhenDetailMissing() {
        let viewModel = makeViewModel(repository: StubAnimeDetailsRepository())
        XCTAssertEqual(viewModel.title, "—")
    }

    func testEpisodeCountUsesKodikCatalogWhenAvailable() async {
        let viewModel = await loaded(
            detail: makeDetail(episodes: 12, episodesAired: 12),
            catalog: [makeCatalogEntry(translationId: 1, episodes: [1, 2, 3, 4, 5, 6, 7, 8])]
        )
        XCTAssertEqual(viewModel.episodeCount, 8)
    }

    func testEpisodeCountFallsBackToDetailWhenNoKodik() async {
        let viewModel = await loaded(detail: makeDetail(episodes: 24, episodesAired: 24))
        XCTAssertEqual(viewModel.episodeCount, 24)
    }

    func testNextEpisodeToWatchClampsAboveOneAndBelowEpisodeCount() async {
        // userRate.episodes = 99, total = 12 → next is clamped to 12.
        let viewModel = await loaded(
            detail: makeDetail(
                episodes: 12,
                episodesAired: 12,
                userRate: UserRateREST(id: 1, score: nil, status: "watching", episodes: 99, rewatches: 0)
            )
        )
        XCTAssertEqual(viewModel.nextEpisodeToWatch, 12)
    }

    func testNextEpisodeToWatchIsAtLeastOne() async {
        // No user rate, no episodes → fallback path returns at least 1.
        let viewModel = await loaded(detail: makeDetail(episodes: 0, episodesAired: 0))
        XCTAssertGreaterThanOrEqual(viewModel.nextEpisodeToWatch, 1)
    }

    func testIsAnonsTrueWhenAnonsFlagSet() async {
        let viewModel = await loaded(detail: makeDetail(status: "anons", anons: true))
        XCTAssertTrue(viewModel.isAnons)
    }

    func testIsAnonsFalseWhenStatusReleased() async {
        let viewModel = await loaded(detail: makeDetail(status: "released"))
        XCTAssertFalse(viewModel.isAnons)
    }

    // MARK: - Posters & previews

    func testPosterURLIgnoresMissingPlaceholder() async {
        // The fixture/`anime_detail.json` populates every image slot with
        // `missing_*.jpg` — VM must not return any of those.
        let viewModel = await loaded(
            detail: makeDetail(image: AnimeImageURLs(
                original: "/assets/globals/missing_original.jpg",
                preview: "/assets/globals/missing_preview.jpg",
                x96: "/assets/globals/missing_x96.jpg",
                x48: "/assets/globals/missing_x48.jpg"
            ))
        )
        XCTAssertNil(viewModel.posterURL)
    }

    func testPosterURLResolvesAbsoluteRESTImage() async {
        let viewModel = await loaded(
            detail: makeDetail(image: AnimeImageURLs(
                original: "https://cdn.example/anime/42.jpg",
                preview: nil,
                x96: nil,
                x48: nil
            ))
        )
        XCTAssertEqual(viewModel.posterURL?.absoluteString, "https://cdn.example/anime/42.jpg")
    }

    func testEpisodePreviewsExtractFromVideos() async {
        let videos = [
            AnimeVideoREST(id: 1, url: nil, imageUrl: "http://img/01.jpg",
                           playerUrl: nil, name: "01", kind: "episode_preview", hosting: nil),
            AnimeVideoREST(id: 2, url: nil, imageUrl: "https://img/03.jpg",
                           playerUrl: nil, name: "03", kind: "episode_preview", hosting: nil),
            AnimeVideoREST(id: 3, url: nil, imageUrl: "https://img/op.jpg",
                           playerUrl: nil, name: "Opening", kind: "op", hosting: nil)
        ]
        let viewModel = await loaded(detail: makeDetail(videos: videos))

        XCTAssertEqual(viewModel.episodePreviews.count, 2)
        // http URL is upgraded to https for ATS compliance.
        XCTAssertEqual(viewModel.episodePreviews[1]?.scheme, "https")
        XCTAssertEqual(viewModel.episodePreviews[3]?.absoluteString, "https://img/03.jpg")
    }

    func testTrailerVideosExcludeEpisodePreviews() async {
        let videos = [
            AnimeVideoREST(id: 1, url: "https://yt/op", imageUrl: nil,
                           playerUrl: nil, name: "OP", kind: "op", hosting: nil),
            AnimeVideoREST(id: 2, url: "https://yt/ep1", imageUrl: nil,
                           playerUrl: nil, name: "01", kind: "episode_preview", hosting: nil),
            AnimeVideoREST(id: 3, url: "https://yt/pv", imageUrl: nil,
                           playerUrl: nil, name: "PV", kind: "pv", hosting: nil)
        ]
        let viewModel = await loaded(detail: makeDetail(videos: videos))

        XCTAssertEqual(viewModel.trailerVideos.map(\.id), [1, 3])
    }

    // MARK: - Helpers

    private func makeViewModel(
        repository: AnimeDetailsRepository,
        shikimoriId: Int = 1
    ) -> AnimeDetailsViewModel {
        AnimeDetailsViewModel(
            shikimoriId: shikimoriId,
            configuration: .testing(),
            currentUserId: nil,
            session: PlaybackSession(),
            kodikClient: KodikClient(),
            repository: repository,
            mutations: NoopUserRateMutating()
        )
    }

    private func loaded(
        detail: AnimeDetail,
        catalog: [KodikCatalogEntry] = [],
        related: [AnimeListItem] = []
    ) async -> AnimeDetailsViewModel {
        let repo = StubAnimeDetailsRepository()
        repo.snapshotResult = .success(
            makeSnapshot(detail: detail, catalog: catalog, related: related)
        )
        let viewModel = makeViewModel(repository: repo, shikimoriId: detail.id)
        await viewModel.load()
        return viewModel
    }

    private func makeSnapshot(
        detail: AnimeDetail,
        catalog: [KodikCatalogEntry] = [],
        related: [AnimeListItem] = []
    ) -> AnimeDetailRepo.Snapshot {
        AnimeDetailRepo.Snapshot(
            detail: detail,
            stats: nil,
            kodikCatalog: catalog,
            screenshots: [],
            videos: detail.videos ?? [],
            related: related
        )
    }

    private func makeCatalogEntry(translationId: Int, episodes: [Int]) -> KodikCatalogEntry {
        let map = Dictionary(uniqueKeysWithValues: episodes.map { ($0, "https://kodik/\($0)") })
        return KodikCatalogEntry(
            translation: KodikTranslation(id: translationId, title: "Studio \(translationId)", kind: .voice),
            episodes: map,
            fallbackLink: nil
        )
    }

    private func makeListItem(id: Int, name: String) -> AnimeListItem {
        AnimeListItem(
            id: id,
            name: name,
            russian: nil,
            image: nil,
            url: nil,
            kind: "tv",
            score: nil,
            status: "released",
            episodes: 12,
            episodesAired: 12,
            airedOn: nil,
            releasedOn: nil
        )
    }

    private func makeDetail(
        id: Int = 1,
        name: String = "Anime",
        russian: String? = "Аниме",
        status: String? = "released",
        anons: Bool? = nil,
        ongoing: Bool? = nil,
        episodes: Int? = 12,
        episodesAired: Int? = 12,
        image: AnimeImageURLs? = nil,
        videos: [AnimeVideoREST]? = nil,
        favoured: Bool? = nil,
        userRate: UserRateREST? = nil
    ) -> AnimeDetail {
        AnimeDetail(
            id: id,
            name: name,
            russian: russian,
            image: image,
            url: nil,
            kind: "tv",
            score: "7.5",
            status: status,
            episodes: episodes,
            episodesAired: episodesAired,
            airedOn: nil,
            releasedOn: nil,
            rating: nil,
            english: nil,
            japanese: nil,
            synonyms: nil,
            licenseNameRu: nil,
            duration: 24,
            description: nil,
            descriptionHtml: nil,
            descriptionSource: nil,
            franchise: nil,
            favoured: favoured,
            anons: anons,
            ongoing: ongoing,
            threadId: nil,
            topicId: nil,
            myanimelistId: nil,
            updatedAt: nil,
            nextEpisodeAt: nil,
            fansubbers: nil,
            fandubbers: nil,
            licensors: nil,
            genres: nil,
            studios: nil,
            videos: videos,
            screenshots: nil,
            userRate: userRate
        )
    }
}

// MARK: - Test doubles

@MainActor
private final class StubAnimeDetailsRepository: AnimeDetailsRepository {
    var cached: AnimeDetailRepo.Snapshot?
    var snapshotResult: Result<AnimeDetailRepo.Snapshot, Error> = .failure(StubError.notSet)
    private(set) var snapshotCallCount = 0

    func cachedSnapshot(id: Int, allowStale: Bool) -> AnimeDetailRepo.Snapshot? {
        cached
    }

    func snapshot(
        id: Int,
        configuration: ShikimoriConfiguration,
        kodikClient: KodikClient,
        forceRefresh: Bool
    ) async throws -> AnimeDetailRepo.Snapshot {
        snapshotCallCount += 1
        return try snapshotResult.get()
    }
}

private enum StubError: Error {
    case unreachable
    case notSet
}

/// Default mutation stub used by VM tests that don't exercise mutation paths.
/// Each method traps if invoked — tests that need mutation behaviour should
/// provide their own conforming double.
@MainActor
private final class NoopUserRateMutating: UserRateMutating {
    func updateUserRate(
        configuration: ShikimoriConfiguration,
        animeId: Int,
        userId: Int,
        rateId: Int,
        status: String?,
        score: Int?,
        episodesWatched: Int?
    ) async throws -> UserRateMutationResult {
        XCTFail("Unexpected updateUserRate call in non-mutation test")
        throw StubError.unreachable
    }

    func createUserRate(
        configuration: ShikimoriConfiguration,
        animeId: Int,
        userId: Int,
        status: String,
        score: Int?,
        episodesWatched: Int?
    ) async throws -> UserRateMutationResult {
        XCTFail("Unexpected createUserRate call in non-mutation test")
        throw StubError.unreachable
    }

    func deleteUserRate(
        configuration: ShikimoriConfiguration,
        animeId: Int,
        userId: Int,
        rateId: Int
    ) async throws {
        XCTFail("Unexpected deleteUserRate call in non-mutation test")
        throw StubError.unreachable
    }

    func toggleFavorite(
        configuration: ShikimoriConfiguration,
        animeId: Int,
        userId: Int,
        currentlyFavorite: Bool
    ) async throws -> Bool {
        XCTFail("Unexpected toggleFavorite call in non-mutation test")
        throw StubError.unreachable
    }
}
