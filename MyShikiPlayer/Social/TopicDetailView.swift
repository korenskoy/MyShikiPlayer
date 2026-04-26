//
//  TopicDetailView.swift
//  MyShikiPlayer
//
//  Full topic: hero (author + title) + body (plain) + linked anime card
//  + list of comments. Opens on top of SocialView.
//

import AppKit
import SwiftUI

struct TopicDetailView: View {
    @Environment(\.appTheme) private var theme
    @StateObject private var vm: TopicDetailViewModel

    let configuration: ShikimoriConfiguration
    let onClose: () -> Void
    let onOpenAnime: (Int) -> Void

    init(
        configuration: ShikimoriConfiguration,
        topic: Topic,
        onClose: @escaping () -> Void,
        onOpenAnime: @escaping (Int) -> Void
    ) {
        self.configuration = configuration
        self.onClose = onClose
        self.onOpenAnime = onOpenAnime
        _vm = StateObject(wrappedValue: TopicDetailViewModel(topicId: topic.id, seed: topic))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                backLink
                if let topic = vm.topic {
                    topicHero(topic)
                    let segments = topicSegments(topic)
                    if !segments.isEmpty {
                        FormattedBody(segments: segments, onOpenAnimeId: onOpenAnime)
                    }
                    if let linked = topic.linked, topic.linkedType == "Anime" {
                        linkedAnimeCard(linked)
                    }
                }

                commentsSection

                Spacer(minLength: 48)
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            .padding(.bottom, 48)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.bg)
        .task {
            await vm.load(configuration: configuration)
        }
    }

    // MARK: - Back link (inline, scrolls with content)

    private var backLink: some View {
        Button(action: onClose) {
            HStack(spacing: 6) {
                DSIcon(name: .chevL, size: 12, weight: .semibold)
                Text("К ленте")
                    .font(.dsMono(11, weight: .medium))
                    .tracking(1)
            }
            .foregroundStyle(theme.fg3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Вернуться к ленте (Esc)")
    }

    // MARK: - Hero

    private func topicHero(_ topic: Topic) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                TopicAvatar(user: topic.user, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.user?.nickname ?? "—")
                        .font(.dsBody(13, weight: .semibold))
                        .foregroundStyle(theme.fg)
                    Text(headerSubline(topic))
                        .font(.dsMono(11))
                        .foregroundStyle(theme.fg3)
                }
                Spacer()
            }
            Text(topic.topicTitle ?? "Без заголовка")
                .font(.dsTitle(26, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(theme.fg)
                .multilineTextAlignment(.leading)
        }
    }

    private func topicSegments(_ topic: Topic) -> [ShikimoriText.Segment] {
        // BBCode markup (body) takes priority — preserves [spoiler] / [quote].
        // If absent, fall back to html_body (HTML spoiler parser not added yet).
        let raw = topic.body?.nilIfEmpty ?? topic.htmlBody
        return ShikimoriText.segments(raw)
    }

    // MARK: - Linked anime card

    private func linkedAnimeCard(_ linked: TopicLinked) -> some View {
        Button {
            guard let id = linked.id else { return }
            onOpenAnime(id)
        } label: {
            HStack(spacing: 14) {
                if let url = linkedPosterURL(linked) {
                    CachedRemoteImage(
                        url: url,
                        contentMode: .fill,
                        placeholder: { Color.clear },
                        failure: { Color.clear }
                    )
                    .frame(width: 60, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("ОБСУЖДАЕТСЯ ТАЙТЛ")
                        .font(.dsLabel(9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(theme.accent)
                    Text(displayLinkedTitle(linked))
                        .font(.dsTitle(15, weight: .semibold))
                        .foregroundStyle(theme.fg)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let score = linked.score, !score.isEmpty, score != "0.0" {
                        Text("Оценка \(score)")
                            .font(.dsMono(11))
                            .foregroundStyle(theme.fg3)
                    }
                }
                Spacer()
                DSIcon(name: .chevR, size: 14, weight: .semibold)
                    .foregroundStyle(theme.fg3)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(theme.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("COMMENTS")
                    .font(.dsLabel(10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(theme.accent)
                Text("Комментарии")
                    .font(.dsTitle(18, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(theme.fg)
                Spacer()
                Text("\(vm.comments.count)")
                    .font(.dsMono(12))
                    .foregroundStyle(theme.fg3)
            }
            if vm.comments.isEmpty && vm.isLoading {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if vm.comments.isEmpty {
                Text("Комментариев пока нет.")
                    .font(.dsBody(12))
                    .foregroundStyle(theme.fg3)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(vm.comments, id: \.id) { comment in
                        CommentRow(comment: comment, onOpenAnimeId: onOpenAnime)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func headerSubline(_ topic: Topic) -> String {
        var parts: [String] = []
        if let forum = topic.forum?.name, !forum.isEmpty {
            parts.append(forum)
        }
        if let created = topic.createdAt {
            let fmt = RelativeDateTimeFormatter()
            fmt.locale = Locale(identifier: "ru_RU")
            fmt.unitsStyle = .short
            parts.append(fmt.localizedString(for: created, relativeTo: Date()))
        }
        return parts.joined(separator: " · ")
    }

    private func linkedPosterURL(_ linked: TopicLinked) -> URL? {
        let raw = linked.image?.preview
            ?? linked.image?.original
            ?? linked.image?.x96
            ?? linked.image?.x48
        guard let raw, !raw.isEmpty, !raw.contains("missing_") else { return nil }
        if raw.hasPrefix("http") { return URL(string: raw) }
        if raw.hasPrefix("/") { return ShikimoriURL.media(path: raw) }
        return URL(string: raw)
    }

    private func displayLinkedTitle(_ linked: TopicLinked) -> String {
        if let r = linked.russian, !r.isEmpty { return r }
        return linked.name ?? "—"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
