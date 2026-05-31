//
//  SimilarSection.swift
//  MyShikiPlayer
//
//  5-column "Similar" grid. Reuses CatalogCard.
//

import SwiftUI

struct SimilarSection: View {
    let items: [AnimeListItem]
    /// Cap on how many cards to render. Default keeps the long-standing
    /// "Похожее" behavior (10); callers wanting a larger grid (e.g. the
    /// franchise section) pass a higher value.
    var limit: Int = 10
    let onOpen: (AnimeListItem) -> Void

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 14, alignment: .top),
        count: 5
    )

    var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(items.prefix(limit), id: \.id) { item in
                    CatalogCard(item: item) { onOpen(item) }
                }
            }
        }
    }
}
