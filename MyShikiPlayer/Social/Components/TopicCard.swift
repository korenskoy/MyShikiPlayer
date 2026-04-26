//
//  TopicCard.swift
//  MyShikiPlayer
//
//  Feed post card: author + title + body preview + linked anime
//  (if present) + footer (forum, date, comments). Tap to open details.
//

import SwiftUI

struct TopicCard: View {
    @Environment(\.appTheme) private var theme
    let topic: Topic
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    header
                    title
                    preview
                    footer
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let linked = topic.linked,
                   topic.linkedType == "Anime",
                   let url = linkedPosterURL(linked) {
                    linkedPoster(url: url)
                }
            }
            .padding(16)
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

    // MARK: - Header (avatar + nickname + date)

    private var header: some View {
        HStack(spacing: 10) {
            TopicAvatar(user: topic.user, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(topic.user?.nickname ?? "—")
                    .font(.dsBody(12, weight: .semibold))
                    .foregroundStyle(theme.fg)
                    .lineLimit(1)
                Text(headerSubline)
                    .font(.dsMono(10))
                    .foregroundStyle(theme.fg3)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var title: some View {
        Text(topic.topicTitle ?? "Без заголовка")
            .font(.dsTitle(16, weight: .semibold))
            .tracking(-0.2)
            .foregroundStyle(theme.fg)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
    }

    private var preview: some View {
        Text(previewText)
            .font(.dsBody(13))
            .foregroundStyle(theme.fg2)
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let count = topic.commentsCount, count > 0 {
                HStack(spacing: 4) {
                    DSIcon(name: .list, size: 11, weight: .medium)
                    Text("\(count)")
                        .font(.dsMono(11, weight: .medium))
                }
                .foregroundStyle(theme.fg3)
            }
            if let linked = topic.linked, topic.linkedType == "Anime" {
                HStack(spacing: 4) {
                    DSIcon(name: .star, size: 11, weight: .medium)
                    Text(displayLinkedTitle(linked))
                        .font(.dsBody(11, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(theme.fg3)
            }
            Spacer()
        }
    }

    // MARK: - Linked poster

    private func linkedPoster(url: URL) -> some View {
        CachedRemoteImage(
            url: url,
            contentMode: .fill,
            placeholder: { Color.clear },
            failure: { Color.clear }
        )
        .frame(width: 54, height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
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

    // MARK: - Derived

    private var headerSubline: String {
        var parts: [String] = []
        if let name = topic.forum?.name, !name.isEmpty {
            parts.append(name)
        }
        if let created = topic.createdAt {
            let fmt = RelativeDateTimeFormatter()
            fmt.locale = Locale(identifier: "ru_RU")
            fmt.unitsStyle = .short
            parts.append(fmt.localizedString(for: created, relativeTo: Date()))
        }
        return parts.joined(separator: " · ")
    }

    private var previewText: String {
        let raw = topic.htmlBody ?? topic.body ?? ""
        let plain = ShikimoriText.toPlain(raw)
        if plain.isEmpty { return "—" }
        return plain
    }

    private func displayLinkedTitle(_ linked: TopicLinked) -> String {
        if let r = linked.russian, !r.isEmpty { return r }
        return linked.name ?? "—"
    }
}
