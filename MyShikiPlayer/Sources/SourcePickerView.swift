//
//  SourcePickerView.swift
//  MyShikiPlayer
//

import SwiftUI

struct SourcePickerView: View {
    @ObservedObject var session: PlaybackSession

    var body: some View {
        HUDPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Источники")
                    .font(.headline)

                if session.availableSources.isEmpty {
                    Text(session.isPreparing
                        ? "Загружаем доступные источники..."
                        : "Для этой серии источники пока не найдены.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.availableSources) { source in
                        Button {
                            session.select(source: source, autoLoadPlayerItem: false)
                        } label: {
                            HStack {
                                Text(source.provider.rawValue.capitalized)
                                    .fontWeight(session.selectedSource == source ? .semibold : .regular)
                                Spacer()
                                Text(source.qualityLabel)
                                    .foregroundStyle(.secondary)
                                if session.selectedSource == source {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
