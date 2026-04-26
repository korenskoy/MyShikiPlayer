//
//  HistoryGrouping.swift
//  MyShikiPlayer
//
//  Groups the history list by calendar day and picks a readable day
//  header ("Today", "Yesterday", "April 25", "April 25 2025").
//  Pure utility — UI calls it on every redraw.
//

import Foundation

enum HistoryGrouping {
    struct Group: Equatable {
        let title: String
        let items: [MergedHistoryItem]
    }

    static func byDay(
        _ items: [MergedHistoryItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Group] {
        var buckets: [(key: DateComponents, items: [MergedHistoryItem])] = []
        var indexByKey: [DateComponents: Int] = [:]

        for item in items {
            let key = calendar.dateComponents([.year, .month, .day], from: item.occurredAt)
            if let idx = indexByKey[key] {
                buckets[idx].items.append(item)
            } else {
                indexByKey[key] = buckets.count
                buckets.append((key: key, items: [item]))
            }
        }

        return buckets.map { bucket in
            Group(
                title: title(for: bucket.key, now: now, calendar: calendar),
                items: bucket.items
            )
        }
    }

    private static func title(
        for components: DateComponents,
        now: Date,
        calendar: Calendar
    ) -> String {
        guard let date = calendar.date(from: components) else { return "—" }
        if calendar.isDateInToday(date) { return "Сегодня" }
        if calendar.isDateInYesterday(date) { return "Вчера" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        let nowYear = calendar.component(.year, from: now)
        let dateYear = calendar.component(.year, from: date)
        formatter.dateFormat = (nowYear == dateYear) ? "d MMMM" : "d MMMM yyyy"
        return formatter.string(from: date).capitalized(with: Locale(identifier: "ru_RU"))
    }
}
