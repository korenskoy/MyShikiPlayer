//
//  TopicSidebar.swift
//  MyShikiPlayer
//
//  Right-hand 320pt rail of TopicDetailView (variant D from the design
//  reference). Hosts: a disabled "Создать топик" CTA (write-scope OAuth
//  not wired yet), the linked-anime poster, and community stats blocks
//  (score distribution + status breakdown). Friends / favourites / clubs /
//  collections rails from the design are deferred to a follow-up PR.
//

import SwiftUI

struct TopicSidebar: View {
    @Environment(\.appTheme) private var theme

    let topic: Topic?
    let stats: GraphQLAnimeStatsEntry?
    let isLoadingStats: Bool
    let onOpenAnime: ((Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            createTopicButton

            if let topic, topic.linkedType == "Anime", let linked = topic.linked {
                RailPosterCTA(linked: linked) { id in onOpenAnime?(id) }
            }

            if let entry = stats {
                if let scores = entry.scoresStats, !scores.isEmpty {
                    ScoreDistributionCard(stats: scores)
                }
                if let statuses = entry.statusesStats, !statuses.isEmpty {
                    RailListsBlock(stats: statuses)
                }
            } else if isLoadingStats {
                statsPlaceholder
            }

            // Friends / Fav / Clubs / Collections rails — deferred. Hooks
            // for the follow-up PR live here.
        }
    }

    private var createTopicButton: some View {
        Button {} label: {
            HStack(spacing: 6) {
                DSIcon(name: .plus, size: 12, weight: .semibold)
                Text("Создать топик")
                    .font(.dsBody(13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(theme.mode == .dark ? Color.black : Color.white)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.45)
        .help("Доступно после авторизации с правом записи")
    }

    private var statsPlaceholder: some View {
        HStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
    }
}
