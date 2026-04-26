//
//  ScheduleView.swift
//  MyShikiPlayer
//
//  Ongoing calendar: vertical sections per day (Today, Tomorrow, …),
//  each containing a 6-column card grid. Time zone follows the device.
//

import SwiftUI

struct ScheduleView: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var auth: ShikimoriAuthController
    @StateObject private var vm = ScheduleViewModel()

    let onOpenDetails: (Int) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 24)
                    .padding(.bottom, 18)

                if vm.sections.isEmpty {
                    emptyOrLoading
                } else {
                    ForEach(vm.sections) { section in
                        daySection(section)
                    }
                }

                Spacer(minLength: 48)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 1440)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.bg)
        .task {
            guard let config = auth.configuration else { return }
            await vm.reload(configuration: config)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("KARENDĀ")
                .font(.dsLabel(10, weight: .bold))
                .tracking(1.8)
                .foregroundStyle(theme.accent)
            Text("Расписание онгоингов")
                .font(.dsTitle(28, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(theme.fg)
            Text("Ближайшие 7 дней · локальное время")
                .font(.dsBody(12))
                .foregroundStyle(theme.fg3)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Day section

    private func daySection(_ section: ScheduleDaySection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(Self.kickerFor(day: section.day))
                    .font(.dsLabel(10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(theme.accent)
                Text(Self.titleFor(day: section.day))
                    .font(.dsTitle(20, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(theme.fg)
                Spacer()
                Text("\(section.entries.count) \(Self.episodeWord(section.entries.count))")
                    .font(.dsMono(11))
                    .foregroundStyle(theme.fg3)
            }
            .padding(.top, 28)
            .padding(.bottom, 14)

            LazyVGrid(columns: cols(6), alignment: .leading, spacing: 14) {
                ForEach(section.entries, id: \.anime.id) { entry in
                    ScheduleEntryCard(entry: entry) { onOpenDetails(entry.anime.id) }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyOrLoading: some View {
        if vm.isLoading {
            HStack {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            }
            .padding(.vertical, 60)
        } else if let message = vm.errorMessage {
            VStack(spacing: 8) {
                Text("Не удалось загрузить расписание")
                    .font(.dsTitle(16, weight: .semibold))
                    .foregroundStyle(theme.fg)
                Text(message)
                    .font(.dsBody(12))
                    .foregroundStyle(theme.fg3)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            Text("На ближайшую неделю ничего не запланировано.")
                .font(.dsBody(13))
                .foregroundStyle(theme.fg3)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 60)
        }
    }

    // MARK: - Helpers

    private func cols(_ count: Int) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: count)
    }

    /// "TODAY", "TOMORROW", "MON", etc. — short accent kicker.
    private static func kickerFor(day: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let diff = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch diff {
        case 0: return "TODAY"
        case 1: return "TOMORROW"
        default:
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.dateFormat = "EEE"
            return fmt.string(from: day).uppercased()
        }
    }

    /// "Wednesday, April 23" — full human-readable date.
    private static func titleFor(day: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.dateFormat = "EEEE, d MMMM"
        return fmt.string(from: day).capitalizedFirst
    }

    private static func episodeWord(_ count: Int) -> String {
        let rem100 = count % 100
        if rem100 >= 11 && rem100 <= 14 { return "серий" }
        switch count % 10 {
        case 1: return "серия"
        case 2, 3, 4: return "серии"
        default: return "серий"
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
