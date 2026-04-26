//
//  FriendActivityCard.swift
//  MyShikiPlayer
//
//  "What a friend is watching" card: avatar + nickname + last 1-3 events.
//  Each event — a row with a verb (watching/rated/finished) and a title
//  + mini poster. Tap the poster to open details.
//

import SwiftUI

struct FriendActivityCard: View {
    @Environment(\.appTheme) private var theme
    let activity: SocialRepo.FriendActivity
    let onOpenAnime: (Int) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TopicAvatar(
                user: TopicUser(
                    id: activity.friend.id,
                    nickname: activity.friend.nickname,
                    avatar: activity.friend.avatar,
                    image: activity.friend.image,
                    lastOnlineAt: activity.friend.lastOnlineAt,
                    url: activity.friend.url
                ),
                size: 36
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(activity.friend.nickname)
                        .font(.dsBody(13, weight: .semibold))
                        .foregroundStyle(theme.fg)
                    Text(latestNote)
                        .font(.dsMono(11))
                        .foregroundStyle(theme.fg3)
                    Spacer()
                }
                ForEach(entriesToShow) { entry in
                    entryRow(entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
    }

    // First 3 events per card — more would visually overload it.
    private var entriesToShow: [UserHistoryEntry] {
        Array(activity.entries.prefix(3))
    }

    private var latestNote: String {
        guard let date = activity.entries.first?.createdAt else { return "" }
        let fmt = RelativeDateTimeFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.unitsStyle = .short
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    private func entryRow(_ entry: UserHistoryEntry) -> some View {
        HStack(alignment: .center, spacing: 10) {
            posterThumb(entry: entry)
            VStack(alignment: .leading, spacing: 3) {
                Text(targetTitle(entry: entry))
                    .font(.dsBody(12, weight: .semibold))
                    .foregroundStyle(theme.fg)
                    .lineLimit(1)
                Text(actionDescription(entry: entry))
                    .font(.dsMono(10))
                    .foregroundStyle(theme.fg3)
                    .lineLimit(1)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if let id = entry.target?.id {
                onOpenAnime(id)
            }
        }
    }

    @ViewBuilder
    private func posterThumb(entry: UserHistoryEntry) -> some View {
        if let url = posterURL(entry: entry) {
            CachedRemoteImage(
                url: url,
                contentMode: .fill,
                placeholder: { theme.bg2 },
                failure: { theme.bg2 }
            )
            .frame(width: 32, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(theme.bg2)
                .frame(width: 32, height: 46)
        }
    }

    private func posterURL(entry: UserHistoryEntry) -> URL? {
        let raw = entry.target?.image?.preview
            ?? entry.target?.image?.original
            ?? entry.target?.image?.x96
            ?? entry.target?.image?.x48
        guard let raw, !raw.isEmpty, !raw.contains("missing_") else { return nil }
        if raw.hasPrefix("http") { return URL(string: raw) }
        if raw.hasPrefix("/") { return ShikimoriURL.media(path: raw) }
        return URL(string: raw)
    }

    private func targetTitle(entry: UserHistoryEntry) -> String {
        if let r = entry.target?.russian, !r.isEmpty { return r }
        return entry.target?.name ?? "—"
    }

    private func actionDescription(entry: UserHistoryEntry) -> String {
        // Shikimori returns description as HTML/BBCode. Strip it.
        let raw = entry.description ?? ""
        let plain = ShikimoriText.toPlain(raw)
        return plain.isEmpty ? "действие" : plain
    }
}
