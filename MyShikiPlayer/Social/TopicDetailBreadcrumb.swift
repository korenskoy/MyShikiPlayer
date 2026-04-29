//
//  TopicDetailBreadcrumb.swift
//  MyShikiPlayer
//
//  "Форум / Аниме и манга / Re:Zero…" trail under the topic title. Lives in
//  its own file to keep `TopicDetailView`'s body inside the SwiftLint length
//  budget.
//

import SwiftUI

extension TopicDetailView {
    /// Trail mirrored after Shikimori's web layout: forum group, forum name,
    /// linked anime (clickable). Hidden when the topic has no forum/linked.
    @ViewBuilder
    func breadcrumb(_ topic: Topic) -> some View {
        let parts = breadcrumbParts(topic)
        if !parts.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(parts.enumerated()), id: \.offset) { idx, part in
                    if idx > 0 {
                        Text("/")
                            .font(.dsMono(11))
                            .foregroundStyle(theme.fg3)
                    }
                    breadcrumbPart(part)
                }
            }
        }
    }

    struct BreadcrumbPart {
        let label: String
        let action: (() -> Void)?
    }

    func breadcrumbParts(_ topic: Topic) -> [BreadcrumbPart] {
        var parts: [BreadcrumbPart] = []
        parts.append(BreadcrumbPart(label: "Форум", action: nil))
        if let forumName = topic.forum?.name, !forumName.isEmpty {
            parts.append(BreadcrumbPart(label: forumName, action: nil))
        }
        if topic.linkedType == "Anime",
           let linked = topic.linked,
           let id = linked.id {
            let label = linked.russian?.nilIfEmpty ?? linked.name?.nilIfEmpty
            if let label {
                parts.append(BreadcrumbPart(label: label, action: { onOpenAnime(id) }))
            }
        }
        return parts
    }

    @ViewBuilder
    func breadcrumbPart(_ part: BreadcrumbPart) -> some View {
        if let action = part.action {
            Button(action: action) {
                Text(part.label)
                    .font(.dsMono(11, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .buttonStyle(.plain)
        } else {
            Text(part.label)
                .font(.dsMono(11))
                .foregroundStyle(theme.fg3)
                .lineLimit(1)
        }
    }
}
