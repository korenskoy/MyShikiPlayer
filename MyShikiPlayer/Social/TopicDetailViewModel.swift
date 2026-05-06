//
//  TopicDetailViewModel.swift
//  MyShikiPlayer
//
//  State for `TopicDetailView`: the topic body, its comments (paginated),
//  pre-parsed `[Segment]` caches for both topic and comments, and reply-
//  target lookups for the flat-thread "ответ на #N" chips.
//

import Foundation
import Combine

@MainActor
final class TopicDetailViewModel: ObservableObject {
    /// Resolved reply target for a comment whose body opens with a
    /// `[comment=…]` reference. The flat-thread row uses this to render a
    /// "ответ на #NNN · @user" chip above the body and to scroll to the
    /// parent on tap.
    struct ParentRef: Equatable {
        let parentId: Int
        let parentIndex: Int
        let authorName: String?
        let snippet: String
    }

    @Published private(set) var topic: Topic?
    /// Comments in ascending order — oldest at the top, newest at the bottom
    /// (matches the Shikimori web layout). The API itself returns descending
    /// pages, so each page is reversed at ingest and prepended to existing
    /// `comments` when paginating further into the past.
    @Published private(set) var comments: [TopicComment] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var canLoadMore: Bool = false
    @Published private(set) var errorMessage: String?

    /// Pre-parsed `ShikimoriText.Segment` lists for the topic body and each
    /// comment, keyed by comment id. We parse once in a detached task at
    /// ingest, then the renderer reads the result without re-running SwiftSoup
    /// on every view rebuild.
    @Published private(set) var topicSegments: [ShikimoriText.Segment] = []
    @Published private(set) var commentSegments: [Int: [ShikimoriText.Segment]] = [:]
    /// Reply-target lookup, keyed by child comment id. Filled in the same
    /// detached parser pass as `commentSegments`.
    @Published private(set) var parentRefs: [Int: ParentRef] = [:]

    /// GraphQL community stats (score / status distributions) for the title
    /// the topic is linked to. `nil` until the sidebar requests it (via
    /// `loadLinkedAnimeStats`); also `nil` for topics that aren't tied to an
    /// anime.
    @Published private(set) var linkedAnimeStats: GraphQLAnimeStatsEntry?
    @Published private(set) var isLoadingLinkedAnimeStats: Bool = false

    let topicId: Int

    /// Highest page number already fetched. Page 1 is the newest batch; each
    /// subsequent page reaches further back. `loadedPages == 0` means we have
    /// only a cache prefill (or nothing yet) and the next fetch must start
    /// from page 1.
    private var loadedPages: Int = 0
    private let pageSize = 30
    private let repository: SocialRepository

    /// Number of paged fetches already merged into `comments`. The flat-thread
    /// page nav reads this together with `totalPages` to render a decorative
    /// "стр. P/T" indicator.
    var loadedPagesCount: Int { loadedPages }
    /// Total comment pages reported by the topic, derived from the topic-level
    /// `commentsCount` and `pageSize`. Returns 0 until the topic has been
    /// resolved.
    var totalPages: Int {
        guard let total = topic?.commentsCount, total > 0 else { return 0 }
        return Int(ceil(Double(total) / Double(pageSize)))
    }

    init(topicId: Int, seed: Topic? = nil, repository: SocialRepository = SocialRepo.shared) {
        self.topicId = topicId
        self.topic = seed
        self.repository = repository
        // Seed body, when present, is the same shape as a fetched topic.
        if seed != nil { Task { await refreshTopicSegments() } }
    }

    // MARK: - Segment caches

    /// Parses the current `topic` body off the main thread, then publishes
    /// the result. Called whenever `topic` is replaced.
    private func refreshTopicSegments() async {
        let raw = topic?.htmlBody?.nilIfEmpty ?? topic?.body
        guard let raw, !raw.isEmpty else {
            topicSegments = []
            return
        }
        let parsed = await Task.detached(priority: .userInitiated) {
            ShikimoriText.segments(raw)
        }.value
        // Drop the result if `topic` was replaced again while we were parsing.
        guard topic?.id == topicId else { return }
        topicSegments = parsed
    }

    /// Parses each comment's body off the main thread and publishes a
    /// `commentId → [Segment]` lookup. Called after `comments` is assigned.
    /// Defensive against duplicate ids — Shikimori's pagination occasionally
    /// returns overlapping batches, so we collapse via `uniquingKeysWith:`
    /// rather than the trap-on-dup `Dictionary(uniqueKeysWithValues:)`.
    private func refreshCommentSegments() async {
        let snapshot = comments.map { ($0.id, $0.htmlBody?.nilIfEmpty ?? $0.body ?? "") }
        let parsed = await Task.detached(priority: .userInitiated) {
            Dictionary(
                snapshot.map { id, raw in (id, ShikimoriText.segments(raw)) },
                uniquingKeysWith: { _, new in new }
            )
        }.value
        // Merge — `loadMore` prepends older pages, so we want to keep
        // already-parsed entries instead of overwriting.
        commentSegments.merge(parsed) { _, new in new }
        recomputeParentRefs()
    }

    /// Resolves each comment's reply target by looking at the leading inline
    /// element of its body. Shikimori's web client puts a `b-mention` link to
    /// the parent comment at the very start of a reply; the HTML parser maps
    /// that to `Inline.commentReference`. Comments whose parent isn't on the
    /// currently-loaded page are skipped (we can't scroll to a row that isn't
    /// rendered). Index is the absolute position in `comments` and is recomputed
    /// from scratch on every call, since `loadMore` prepends older pages and
    /// shifts everyone's index.
    private func recomputeParentRefs() {
        var indexById: [Int: Int] = [:]
        indexById.reserveCapacity(comments.count)
        for (i, c) in comments.enumerated() { indexById[c.id] = i }

        var refs: [Int: ParentRef] = [:]
        for comment in comments {
            guard let segments = commentSegments[comment.id],
                  let parentId = leadingCommentReferenceId(in: segments) else { continue }
            guard let parentIndex = indexById[parentId] else { continue }
            let parent = comments[parentIndex]
            let raw = parent.htmlBody?.nilIfEmpty ?? parent.body ?? ""
            let plain = ShikimoriText.toPlain(raw)
            let snippet = String(plain.prefix(70))
            let suffix = plain.count > 70 ? "…" : ""
            refs[comment.id] = ParentRef(
                parentId: parentId,
                parentIndex: parentIndex,
                authorName: parent.user?.nickname,
                snippet: snippet + suffix
            )
        }
        parentRefs = refs
    }

    /// Returns the parent comment id when the body opens with a `b-mention`
    /// link to another comment. Whitespace-only text inlines are skipped so a
    /// stray newline or space at the start doesn't hide the reference.
    private func leadingCommentReferenceId(
        in segments: [ShikimoriText.Segment]
    ) -> Int? {
        guard let first = segments.first else { return nil }
        let raw: String
        switch first {
        case .plain(let s): raw = s
        case .heading(_, let s): raw = s
        case .markdownQuote(let s): raw = s
        default: return nil
        }
        let inlines = ShikimoriText.parseInlines(raw)
        for inline in inlines {
            switch inline {
            case .text(let s) where s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                continue
            case .commentReference(let id, _):
                return id
            default:
                return nil
            }
        }
        return nil
    }

    func load(configuration: ShikimoriConfiguration) async {
        if let cached = repository.cachedTopic(id: topicId, allowStale: true) {
            topic = cached
            await refreshTopicSegments()
        }
        if let cachedComments = repository.cachedComments(topicId: topicId, allowStale: true) {
            // Cache stores raw API order (desc); flip for ascending display.
            comments = cachedComments.reversed()
            loadedPages = 1
            recomputeCanLoadMore(latestPageSize: cachedComments.count)
            await refreshCommentSegments()
        } else {
            isLoading = true
        }
        errorMessage = nil

        async let topicResult = repository.topic(
            configuration: configuration,
            id: topicId,
            forceRefresh: false
        )
        async let commentsResult = repository.comments(
            configuration: configuration,
            topicId: topicId,
            forceRefresh: false
        )

        do {
            topic = try await topicResult
            await refreshTopicSegments()
        } catch {
            if topic == nil {
                errorMessage = error.localizedDescription
            }
        }
        do {
            let firstPage = try await commentsResult
            comments = firstPage.reversed()
            loadedPages = 1
            recomputeCanLoadMore(latestPageSize: firstPage.count)
            await refreshCommentSegments()
        } catch {
            NetworkLogStore.shared.logAppError(
                "social_comments_failed topic=\(topicId) err=\(error.localizedDescription)"
            )
        }
        isLoading = false
    }

    /// Forces a fresh fetch of both topic body and the first comments page.
    /// Resets pagination — older pages must be re-walked via `loadMore`.
    func reload(configuration: ShikimoriConfiguration) async {
        isLoading = true
        errorMessage = nil
        // Drop the segment cache so reload reparses from scratch (cheap; the
        // detached parses will rebuild it). `parentRefs` is rebuilt by the
        // same pass, but reset it explicitly so a brief render gap doesn't
        // show stale parent chips against a half-loaded comment list.
        commentSegments = [:]
        parentRefs = [:]
        async let topicResult = repository.topic(
            configuration: configuration,
            id: topicId,
            forceRefresh: false
        )
        async let commentsResult = repository.comments(
            configuration: configuration,
            topicId: topicId,
            forceRefresh: true
        )
        do {
            topic = try await topicResult
            await refreshTopicSegments()
        } catch {
            NetworkLogStore.shared.logAppError(
                "social_topic_reload_failed topic=\(topicId) err=\(error.localizedDescription)"
            )
        }
        do {
            let firstPage = try await commentsResult
            comments = firstPage.reversed()
            loadedPages = 1
            recomputeCanLoadMore(latestPageSize: firstPage.count)
            await refreshCommentSegments()
        } catch {
            NetworkLogStore.shared.logAppError(
                "social_comments_reload_failed topic=\(topicId) err=\(error.localizedDescription)"
            )
        }
        isLoading = false
    }

    /// Loads the next older page and prepends it to `comments` so the
    /// ascending layout holds. No-op if a load is already in flight or there
    /// is nothing more to fetch.
    func loadMore(configuration: ShikimoriConfiguration) async {
        guard canLoadMore, !isLoadingMore, loadedPages > 0 else { return }
        isLoadingMore = true
        let nextPage = loadedPages + 1
        do {
            let page = try await repository.commentsPage(
                configuration: configuration,
                topicId: topicId,
                page: nextPage
            )
            // The API returns desc; reverse the batch to keep oldest at the
            // very top, then prepend so the previously-loaded ones stay below.
            // Dedup by id — Shikimori occasionally returns overlapping pages
            // when comments appeared between fetches, and a duplicate in
            // `comments` would later crash `refreshCommentSegments`'s dict.
            let existing = Set(comments.map(\.id))
            let fresh = page.filter { !existing.contains($0.id) }
            comments.insert(contentsOf: fresh.reversed(), at: 0)
            loadedPages = nextPage
            recomputeCanLoadMore(latestPageSize: page.count)
            await refreshCommentSegments()
        } catch {
            NetworkLogStore.shared.logAppError(
                "social_comments_load_more_failed topic=\(topicId) page=\(nextPage) err=\(error.localizedDescription)"
            )
        }
        isLoadingMore = false
    }

    /// Lazy-loads community score / status distributions for the linked
    /// anime so the topic sidebar can render the score histogram and the
    /// status breakdown. No-op for topics without a linked anime, and
    /// memoised — calling it more than once is cheap.
    func loadLinkedAnimeStats(configuration: ShikimoriConfiguration) async {
        guard let topic, topic.linkedType == "Anime",
              let linkedId = topic.linkedId else { return }
        if linkedAnimeStats != nil { return }
        if isLoadingLinkedAnimeStats { return }
        isLoadingLinkedAnimeStats = true
        defer { isLoadingLinkedAnimeStats = false }
        let gql = ShikimoriGraphQLClient(configuration: configuration)
        do {
            linkedAnimeStats = try await gql.animeStats(id: linkedId)
        } catch {
            NetworkLogStore.shared.logAppError(
                "social_topic_anime_stats_failed topic=\(topicId) "
                + "linked=\(linkedId) err=\(error.localizedDescription)"
            )
        }
    }

    /// `canLoadMore` is `false` once either the API returned a short page
    /// (no more data) or the loaded count caught up with `topic.commentsCount`.
    private func recomputeCanLoadMore(latestPageSize: Int) {
        if latestPageSize < pageSize {
            canLoadMore = false
            return
        }
        if let total = topic?.commentsCount, comments.count >= total {
            canLoadMore = false
            return
        }
        canLoadMore = true
    }
}
