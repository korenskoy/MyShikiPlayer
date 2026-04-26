//
//  ScheduleEntryCard.swift
//  MyShikiPlayer
//
//  2:3 poster + name + "HH:mm · EP. N". Used in the ScheduleView grid.
//

import SwiftUI

struct ScheduleEntryCard: View {
    @Environment(\.appTheme) private var theme
    let entry: CalendarEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    CatalogPoster(item: entry.anime)
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)

                    if let episode = entry.estimatedEpisodeNumber {
                        Text("ЭП. \(episode)")
                            .font(.dsMono(10, weight: .semibold))
                            .tracking(1)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color.black.opacity(0.6))
                            )
                            .padding(8)
                    }
                }

                Text(title)
                    .font(.dsBody(13, weight: .semibold))
                    .foregroundStyle(theme.fg)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(metaText)
                    .font(.dsMono(10))
                    .foregroundStyle(theme.fg3)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        if let r = entry.anime.russian, !r.isEmpty { return r }
        return entry.anime.name
    }

    private var metaText: String {
        let timeFmt = DateFormatter()
        timeFmt.locale = Locale(identifier: "ru_RU")
        timeFmt.dateFormat = "HH:mm"
        var parts: [String] = [timeFmt.string(from: entry.nextEpisodeAt)]
        if let dur = entry.duration, dur > 0 {
            parts.append("\(dur) мин")
        }
        return parts.joined(separator: " · ")
    }
}
