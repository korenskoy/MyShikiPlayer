//
//  HistoryRow.swift
//  MyShikiPlayer
//
//  A single row of the History screen: poster + title + action + relative
//  time + (for local entries) a delete icon that appears on hover/focus.
//  No right-click menu is used — the user explicitly asked for an icon.
//

import SwiftUI

struct HistoryRow: View {
    @Environment(\.appTheme) private var theme
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    let item: MergedHistoryItem
    let onOpen: () -> Void
    let onRemoveLocal: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            poster
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.dsBody(13, weight: .semibold))
                    .foregroundStyle(theme.fg)
                    .lineLimit(1)
                Text(actionLine)
                    .font(.dsMono(11))
                    .foregroundStyle(theme.fg3)
                    .lineLimit(1)
            }
            Spacer()
            Text(relativeTime)
                .font(.dsMono(11))
                .foregroundStyle(theme.fg3)
                .padding(.trailing, 8)

            // Fixed-width slot — the icon appears via opacity so the row's
            // content doesn't jitter on hover (see UI stability rule).
            ZStack {
                if item.isLocal {
                    Button(action: onRemoveLocal) {
                        DSIcon(name: .xmark, size: 12, weight: .semibold)
                            .foregroundStyle(theme.fg2)
                            .frame(width: 26, height: 26)
                            .background(
                                Circle().fill(theme.chipBg)
                            )
                            .overlay(
                                Circle().stroke(theme.line, lineWidth: 1)
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focused($isFocused)
                    .help("Удалить из локальной истории")
                    .opacity(isHovered || isFocused ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
                    .animation(.easeInOut(duration: 0.15), value: isFocused)
                }
            }
            .frame(width: 26, height: 26)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? theme.bg2 : theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: onOpen)
    }

    // MARK: - Poster

    @ViewBuilder
    private var poster: some View {
        if let url = posterURL {
            CachedRemoteImage(
                url: url,
                contentMode: .fill,
                placeholder: { theme.bg2 },
                failure: { theme.bg2 }
            )
            .frame(width: 36, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(theme.bg2)
                .frame(width: 36, height: 52)
        }
    }

    private var posterURL: URL? {
        // 1. Remote event already carries a ready URL.
        if let raw = item.posterURL, !raw.isEmpty { return URL(string: raw) }
        // 2. Local — ask PosterEnricher (shared poster cache).
        if let cached = PosterEnricher.shared.cachedURL(id: item.shikimoriId) {
            return URL(string: cached)
        }
        return nil
    }

    // MARK: - Texts

    private var actionLine: String {
        switch item.source {
        case let .local(action, _):
            let prefix = localActionPrefix(action)
            if let ep = item.episode {
                return "\(prefix) · эпизод \(ep)"
            }
            return prefix
        case let .remote(rawDescription):
            return rawDescription.isEmpty ? "событие" : rawDescription
        }
    }

    private func localActionPrefix(_ action: WatchHistoryStore.Action) -> String {
        switch action {
        case .started:   return "Открыт"
        case .progress:  return "В процессе"
        case .completed: return "Досмотрен"
        }
    }

    private var relativeTime: String {
        let fmt = RelativeDateTimeFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.unitsStyle = .short
        return fmt.localizedString(for: item.occurredAt, relativeTo: Date())
    }
}
