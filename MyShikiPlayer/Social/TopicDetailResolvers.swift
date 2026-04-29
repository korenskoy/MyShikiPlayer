//
//  TopicDetailResolvers.swift
//  MyShikiPlayer
//
//  Builds `CommentResolvers` from the topic + comments payload. Only
//  comment-author lookups are needed now: image URLs and entity titles
//  come pre-resolved in `html_body`, parsed by `ShikimoriHTML`.
//
//  Lives in its own file so `TopicDetailView`'s body stays inside SwiftLint's
//  type-length budget.
//

import Foundation

extension TopicDetailView {
    /// Lookup tables built from the currently-loaded page of comments.
    /// Powers the `[comment=N]` chip rendering — the chip needs the
    /// commented author's nickname to show "@nick" rather than "→к комменту".
    func buildCommentResolvers() -> CommentResolvers {
        var byAuthor: [Int: String] = [:]
        var byComment: [Int: String] = [:]
        for c in vm.comments {
            guard let nick = c.user?.nickname, !nick.isEmpty else { continue }
            byComment[c.id] = nick
            if let aid = c.user?.id {
                byAuthor[aid] = nick
            }
        }
        return CommentResolvers(
            nickByAuthorId: { byAuthor[$0] },
            nickByCommentId: { byComment[$0] }
        )
    }

    /// Topic body has no comment context (we only render the OP, not its
    /// thread), so the resolvers can be empty.
    func buildTopicResolvers() -> CommentResolvers { .empty }
}
