//
//  DescriptionSection.swift
//  MyShikiPlayer
//
//  Title synopsis. Shikimori returns BBCode (`[anime=N]Name[/anime]`,
//  `[character=N]…[/character]`, `[url]…[/url]`, `[b]`, `[spoiler]`, …).
//  Rendering goes through FormattedBody → AttributedString — entity links
//  are clickable. The "expand fully" button uses a character threshold:
//  on a wide column (~720) 8 lines ≈ 800 characters; below the threshold
//  the text is assumed to fit visually and does not need collapsing.
//

import SwiftUI

struct DescriptionSection: View {
    @Environment(\.appTheme) private var theme
    let rawDescription: String?
    let onOpenAnimeId: ((Int) -> Void)?

    @State private var expanded = false

    private let collapsedLineLimit: Int = 8
    private let collapseCharThreshold: Int = 800

    init(rawDescription: String?, onOpenAnimeId: ((Int) -> Void)? = nil) {
        self.rawDescription = rawDescription
        self.onOpenAnimeId = onOpenAnimeId
    }

    private var segments: [ShikimoriText.Segment] {
        ShikimoriText.segments(rawDescription)
    }

    private var plainPreview: String {
        ShikimoriText.toPlain(rawDescription)
    }

    private var hasContent: Bool { !plainPreview.isEmpty }

    private var canExpand: Bool {
        plainPreview.count > collapseCharThreshold
    }

    var body: some View {
        if !hasContent {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                FormattedBody(
                    segments: segments,
                    font: .dsBody(14),
                    lineSpacing: 4,
                    onOpenAnimeId: onOpenAnimeId
                )
                .lineLimit(canExpand && !expanded ? collapsedLineLimit : nil)
                .frame(maxWidth: 720, alignment: .leading)

                if canExpand {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text(expanded ? "свернуть" : "раскрыть полностью")
                                .font(.dsMono(12, weight: .medium))
                            DSIcon(name: expanded ? .chevU : .chevD, size: 11, weight: .bold)
                        }
                        .foregroundStyle(theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
