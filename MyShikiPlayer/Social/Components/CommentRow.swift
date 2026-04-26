//
//  CommentRow.swift
//  MyShikiPlayer
//
//  Single row in the comments list: avatar + nickname + date + body (plain).
//

import SwiftUI

struct CommentRow: View {
    @Environment(\.appTheme) private var theme
    let comment: TopicComment
    var onOpenAnimeId: ((Int) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TopicAvatar(user: comment.user, size: 32)
            VStack(alignment: .leading, spacing: 6) {
                header
                bodyText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(comment.user?.nickname ?? "—")
                .font(.dsBody(12, weight: .semibold))
                .foregroundStyle(theme.fg)
                .lineLimit(1)
            if let created = comment.createdAt {
                Text(Self.relativeDate(created))
                    .font(.dsMono(10))
                    .foregroundStyle(theme.fg3)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var bodyText: some View {
        let segments = commentSegments
        if segments.isEmpty {
            Text("—")
                .font(.dsBody(13))
                .foregroundStyle(theme.fg3)
        } else {
            FormattedBody(segments: segments, font: .dsBody(13), lineSpacing: 3, onOpenAnimeId: onOpenAnimeId)
        }
    }

    private var commentSegments: [ShikimoriText.Segment] {
        // Prefer BBCode body (spoilers/quotes still in [brackets]).
        let raw = (comment.body?.isEmpty == false ? comment.body : comment.htmlBody) ?? ""
        return ShikimoriText.segments(raw)
    }

    private static func relativeDate(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.unitsStyle = .short
        return fmt.localizedString(for: date, relativeTo: Date())
    }
}
