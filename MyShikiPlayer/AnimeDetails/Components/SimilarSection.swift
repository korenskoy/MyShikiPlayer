//
//  SimilarSection.swift
//  MyShikiPlayer
//
//  5-column "Similar" grid. Reuses CatalogCard.
//

import SwiftUI

struct SimilarSection: View {
    let items: [AnimeListItem]
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
                ForEach(items.prefix(10), id: \.id) { item in
                    CatalogCard(item: item) { onOpen(item) }
                }
            }
        }
    }
}
