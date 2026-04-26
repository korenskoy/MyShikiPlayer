//
//  SearchModalView.swift
//  MyShikiPlayer
//
//  Spotlight-like modal search via ⌘K: 720pt card on top, blurred backdrop,
//  results with ↑↓ navigation and ↵ selection. Opens as overlay in
//  AppShellView, closes on Esc / outside click / result selection.
//

import AppKit
import SwiftUI

struct SearchModalView: View {
    @Environment(\.appTheme) private var theme
    @StateObject private var vm: SearchViewModel
    @FocusState private var inputFocused: Bool
    @State private var selectedIndex: Int = 0

    let onClose: () -> Void
    let onSelect: (AnimeListItem) -> Void

    init(
        configuration: ShikimoriConfiguration?,
        onClose: @escaping () -> Void,
        onSelect: @escaping (AnimeListItem) -> Void
    ) {
        self.onClose = onClose
        self.onSelect = onSelect
        _vm = StateObject(wrappedValue: SearchViewModel(configuration: configuration))
    }

    var body: some View {
        ZStack(alignment: .top) {
            backdrop

            card
                .frame(width: 720)
                .padding(.top, 80)
                .shadow(color: Color.black.opacity(0.35), radius: 30, x: 0, y: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onAppear {
            inputFocused = true
        }
        .onChange(of: vm.results.count) { _, _ in
            selectedIndex = 0
        }
    }

    // MARK: - Layers

    private var backdrop: some View {
        theme.bg.opacity(0.85)
            .background(.ultraThinMaterial)
            .contentShape(Rectangle())
            .onTapGesture { onClose() }
    }

    private var card: some View {
        VStack(spacing: 0) {
            inputRow
            Divider().background(theme.line)
            resultsArea
            Divider().background(theme.line)
            footer
        }
        .background(theme.card)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.line2, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var inputRow: some View {
        HStack(spacing: 14) {
            DSIcon(name: .search, size: 18, weight: .semibold)
                .foregroundStyle(theme.fg2)

            TextField("Найти аниме…", text: $vm.query)
                .textFieldStyle(.plain)
                .font(.dsBody(16))
                .foregroundStyle(theme.fg)
                .focused($inputFocused)
                .onSubmit { activateSelection() }

            if vm.isSearching {
                ProgressView().controlSize(.small)
            }

            Text("ESC")
                .font(.dsMono(10, weight: .semibold))
                .foregroundStyle(theme.fg3)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(theme.line2, lineWidth: 1)
                )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard !vm.results.isEmpty else { return .ignored }
            selectedIndex = min(vm.results.count - 1, selectedIndex + 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            guard !vm.results.isEmpty else { return .ignored }
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
    }

    @ViewBuilder
    private var resultsArea: some View {
        if vm.query.trimmingCharacters(in: .whitespaces).isEmpty {
            emptyState(
                title: "Начни вводить название",
                subtitle: "Поиск по каталогу Shikimori — жанры, студии, имена персонажей."
            )
        } else if vm.results.isEmpty && !vm.isSearching {
            emptyState(title: "Ничего не найдено", subtitle: "Попробуй другой запрос.")
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    sectionHeader("АНИМЕ · \(vm.results.count) \(matchWord(vm.results.count))")
                    VStack(spacing: 2) {
                        ForEach(Array(vm.results.enumerated()), id: \.element.id) { index, item in
                            SearchResultRow(
                                item: item,
                                query: vm.query,
                                isSelected: index == selectedIndex,
                                onTap: { onSelect(item) }
                            )
                            .id(item.id)
                            .onHover { inside in
                                if inside { selectedIndex = index }
                            }
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 440)
            .onChange(of: selectedIndex) { _, new in
                guard vm.results.indices.contains(new) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(vm.results[new].id, anchor: .center)
                }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .dsMonoLabel(size: 10, tracking: 1.5)
            .foregroundStyle(theme.fg3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    private func emptyState(title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.dsBody(14, weight: .semibold))
                .foregroundStyle(theme.fg2)
            Text(subtitle)
                .font(.dsBody(12))
                .foregroundStyle(theme.fg3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private var footer: some View {
        HStack(spacing: 16) {
            footerHint("↑↓", text: "навигация")
            footerHint("↵", text: "открыть")
            Spacer()
            if let ms = vm.elapsedMs, !vm.isSearching {
                Text("поиск за \(ms) мс")
                    .font(.dsMono(10))
                    .foregroundStyle(theme.fg3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func footerHint(_ key: String, text: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.dsMono(10, weight: .semibold))
                .foregroundStyle(theme.fg3)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(theme.line2, lineWidth: 1)
                )
            Text(text)
                .font(.dsBody(11))
                .foregroundStyle(theme.fg3)
        }
    }

    // MARK: - Helpers

    private func activateSelection() {
        guard vm.results.indices.contains(selectedIndex) else { return }
        onSelect(vm.results[selectedIndex])
    }

    private func matchWord(_ count: Int) -> String {
        let rem100 = count % 100
        if rem100 >= 11 && rem100 <= 14 { return "совпадений" }
        switch count % 10 {
        case 1:       return "совпадение"
        case 2, 3, 4: return "совпадения"
        default:      return "совпадений"
        }
    }
}

// MARK: - Row

private struct SearchResultRow: View {
    @Environment(\.appTheme) private var theme
    let item: AnimeListItem
    let query: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                CatalogPoster(item: item, cornerRadius: 4, showsScoreBadge: false)
                    .frame(width: 40, height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    highlightedTitle
                        .font(.dsBody(13, weight: .semibold))
                        .foregroundStyle(theme.fg)
                        .lineLimit(1)
                    Text(metaLine)
                        .font(.dsMono(10))
                        .foregroundStyle(theme.fg3)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let score = scoreValue {
                    HStack(spacing: 4) {
                        DSIcon(name: .star, size: 11, weight: .bold)
                        Text(String(format: "%.2f", score))
                            .font(.dsMono(11, weight: .semibold))
                    }
                    .foregroundStyle(scoreColor(score))
                }

                if isSelected {
                    Text("↵")
                        .font(.dsMono(10, weight: .semibold))
                        .foregroundStyle(theme.fg3)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(theme.line2, lineWidth: 1)
                        )
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? theme.chipBg : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var highlightedTitle: some View {
        let title = displayTitle
        let q = query.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty, let range = title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) {
            let before = String(title[title.startIndex..<range.lowerBound])
            let hit = String(title[range])
            let after = String(title[range.upperBound..<title.endIndex])
            Text(before)
              + Text(hit).foregroundStyle(theme.accent).fontWeight(.bold)
              + Text(after)
        } else {
            Text(title)
        }
    }

    private var displayTitle: String {
        if let r = item.russian, !r.isEmpty { return r }
        return item.name
    }

    private var metaLine: String {
        var parts: [String] = [item.name]
        if let year = (item.releasedOn ?? item.airedOn).flatMap({ $0.count >= 4 ? String($0.prefix(4)) : nil }) {
            parts.append(year)
        }
        if let ep = item.episodes, ep > 0 { parts.append("\(ep) эп") }
        return parts.joined(separator: " · ")
    }

    private var scoreValue: Double? {
        guard let raw = item.score, !raw.isEmpty, raw != "0.0", raw != "0" else { return nil }
        return Double(raw)
    }

    private func scoreColor(_ value: Double) -> Color {
        if value >= 9 { return theme.accent }
        if value >= 8 { return theme.warn }
        if value >= 7 { return theme.good }
        return theme.fg2
    }
}
