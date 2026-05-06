//
//  LinearPostRow.swift
//  MyShikiPlayer
//
//  Forum-style flat post (variant D from the design reference). A row is two
//  columns: a 180pt meta column on the left (post number, avatar, nickname,
//  relative time, "АВТОР" badge, and "опубл. HH:MM" pinned to the bottom)
//  and the body column on the right (optional parent-reference chip,
//  FormattedBody, and a single "🔗 ссылка" footer action that copies the
//  Shikimori URL of the comment to the pasteboard).
//

import AppKit
import SwiftUI

struct LinearPostRow: View {
    @Environment(\.appTheme) private var theme

    let comment: TopicComment
    let isFirst: Bool
    let segments: [ShikimoriText.Segment]?
    /// True when this comment's author is the topic starter — surfaces an
    /// accented "АВТОР" badge in the meta column.
    let isTopicAuthor: Bool
    /// Reference to the parent comment (if this post is a direct reply). When
    /// non-nil, a tappable chip is rendered above the body.
    let parentRef: TopicDetailViewModel.ParentRef?
    /// Briefly true after another post's chip jumped to this row, so we can
    /// flash the surface to confirm the scroll target.
    let isHighlighted: Bool

    var onOpenAnimeId: ((Int) -> Void)? = nil
    var onOpenCommentId: ((Int) -> Void)? = nil
    var onOpenImageURL: ((URL) -> Void)? = nil
    var commentResolvers: CommentResolvers = .empty
    var onJumpToParent: ((Int) -> Void)? = nil

    @State private var copyFeedback: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            metaColumn
                .frame(width: 180, alignment: .leading)
                .padding(.trailing, 18)
            bodyColumn
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 18)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(theme.line)
                    .frame(height: 1)
            }
        }
        .background(
            (isHighlighted ? theme.bg2 : Color.clear)
                .animation(.easeOut(duration: 0.6), value: isHighlighted)
        )
    }

    // MARK: - Meta column

    private var metaColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                TopicAvatar(user: comment.user, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(comment.user?.nickname ?? "—")
                        .font(.dsBody(12.5, weight: .bold))
                        .foregroundStyle(isTopicAuthor ? theme.accent : theme.fg)
                        .lineLimit(1)
                    Text(relativeAgo)
                        .font(.dsMono(9.5))
                        .foregroundStyle(theme.fg3)
                }
            }

            if isTopicAuthor { authorBadge }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if let posted = postedHHMM {
                    Text("опубл. \(posted)")
                        .font(.dsMono(9.5))
                        .foregroundStyle(theme.fg3)
                }
                copyLinkButton
                Text(verbatim: "#\(comment.id)")
                    .font(.dsMono(9.5))
                    .foregroundStyle(theme.fg3)
            }
        }
    }

    /// Compact icon-only "copy comment URL" affordance. Lives in the meta
    /// column so the body footer stays empty and we keep a single visual
    /// anchor per post for "share this comment". Feedback flips the icon
    /// to a check-mark for ~1.5s — the icon is rendered inside a fixed
    /// 14×14pt frame so the SF Symbol intrinsic-bbox difference between
    /// `link` and `checkmark` cannot shift the row's vertical metrics.
    private var copyLinkButton: some View {
        Button(action: copyLink) {
            DSIcon(
                name: copyFeedback ? .check : .link,
                size: 11,
                weight: .semibold
            )
            .frame(width: 14, height: 14, alignment: .center)
            .foregroundStyle(copyFeedback ? theme.good : theme.fg3)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(theme.chipBg.opacity(0.6))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Скопировать ссылку на пост")
    }

    private var authorBadge: some View {
        Text("АВТОР")
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .tracking(1)
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(theme.accent.opacity(0.12))
            )
    }

    // MARK: - Body column

    private var bodyColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let parentRef { parentChip(parentRef) }
            bodyContent
        }
    }

    @ViewBuilder
    private func parentChip(_ ref: TopicDetailViewModel.ParentRef) -> some View {
        Button {
            onJumpToParent?(ref.parentId)
        } label: {
            HStack(spacing: 6) {
                DSIcon(name: .chevR, size: 11, weight: .semibold)
                    .foregroundStyle(theme.accent)
                Text(verbatim: "ответ на #\(ref.parentId)")
                    .foregroundStyle(theme.fg3)
                if let nick = ref.authorName, !nick.isEmpty {
                    Text("· @\(nick)")
                        .foregroundStyle(theme.accent)
                }
                if !ref.snippet.isEmpty {
                    Text("\u{201C}\(ref.snippet)\u{201D}")
                        .foregroundStyle(theme.fg3.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.dsMono(10.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(theme.bg2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(theme.line2, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Перейти к посту-родителю")
    }

    @ViewBuilder
    private var bodyContent: some View {
        if let segments, !segments.isEmpty {
            FormattedBody(
                segments: segments,
                font: .dsBody(13.5),
                lineSpacing: 4,
                onOpenAnimeId: onOpenAnimeId,
                onOpenCommentId: onOpenCommentId,
                onOpenImageURL: onOpenImageURL,
                commentResolvers: commentResolvers
            )
        } else if segments == nil {
            // Cache miss while the detached parser hasn't finished this id.
            Text("…")
                .font(.dsBody(13.5))
                .foregroundStyle(theme.fg3)
        } else {
            Text("—")
                .font(.dsBody(13.5))
                .foregroundStyle(theme.fg3)
        }
    }

    // MARK: - Helpers

    private var relativeAgo: String {
        guard let created = comment.createdAt else { return "" }
        return SocialDateFormatters.relativeRu.localizedString(for: created, relativeTo: Date())
    }

    private var postedHHMM: String? {
        guard let created = comment.createdAt else { return nil }
        return SocialDateFormatters.hhmmRu.string(from: created)
    }

    private func copyLink() {
        let url = "https://shikimori.one/comments/\(comment.id)"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { copyFeedback = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.15)) { copyFeedback = false }
            }
        }
    }
}
