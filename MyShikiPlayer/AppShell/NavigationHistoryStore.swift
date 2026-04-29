//
//  NavigationHistoryStore.swift
//  MyShikiPlayer
//
//  Global browser-style navigation history: tabs + opened title cards.
//  The cursor moves back/forward (like WebKit), while a new push trims the
//  forward portion of the stack. Serialized to UserDefaults — survives across sessions.
//

import Foundation
import Combine

@MainActor
final class NavigationHistoryStore: ObservableObject {
    enum Entry: Equatable, Codable {
        case branch(NavigationState.Branch)
        case detail(shikimoriId: Int, title: String?)
        /// A sub-tab inside the Social branch (Friends / Discussions / Reviews).
        case socialTab(SocialTab)
        /// An opened forum topic inside the Social branch.
        case socialTopic(id: Int, title: String?)
    }

    // MARK: - State

    @Published private(set) var stack: [Entry] = []
    @Published private(set) var cursor: Int = -1

    /// Set to true during `goBack/goForward` so that consumers
    /// (AppShellView) don't push back the same changes that we ourselves
    /// just applied.
    private(set) var isNavigating: Bool = false

    private let maxStackSize = 50
    /// Bumped to v2 when `Entry` gained `socialTab`/`socialTopic`. Old v1
    /// payloads cannot be decoded by the new schema, so we just start fresh.
    private let persistKey = "app.navigationHistory.v2"

    // MARK: - Lifecycle

    init() {
        load()
    }

    // MARK: - Derived

    var canGoBack: Bool { cursor > 0 }
    var canGoForward: Bool { cursor >= 0 && cursor < stack.count - 1 }

    var currentEntry: Entry? {
        guard cursor >= 0, cursor < stack.count else { return nil }
        return stack[cursor]
    }

    var previousEntry: Entry? {
        guard cursor > 0 else { return nil }
        return stack[cursor - 1]
    }

    var nextEntry: Entry? {
        guard cursor >= 0, cursor < stack.count - 1 else { return nil }
        return stack[cursor + 1]
    }

    // MARK: - Mutations

    func push(_ entry: Entry) {
        // Dedup: clicking the entry that is already current — ignore.
        if let current = currentEntry, current == entry { return }

        // Trim the forward portion: a new push = a new history branch.
        if cursor >= 0, cursor < stack.count - 1 {
            stack.removeSubrange((cursor + 1)...)
        }

        stack.append(entry)

        // Length cap: drop the oldest entries.
        if stack.count > maxStackSize {
            let overflow = stack.count - maxStackSize
            stack.removeFirst(overflow)
            cursor = stack.count - 1
        } else {
            cursor = stack.count - 1
        }

        persist()
    }

    /// Updates the title of a detail-entry (for example, once the anime has
    /// loaded and its title is known — replaces the "Loading…" placeholder).
    func updateDetailTitle(shikimoriId: Int, title: String) {
        var mutated = false
        for i in stack.indices {
            if case let .detail(id, existing) = stack[i], id == shikimoriId, existing != title {
                stack[i] = .detail(shikimoriId: id, title: title)
                mutated = true
            }
        }
        if mutated { persist() }
    }

    /// Same as `updateDetailTitle`, but for a forum topic — replaces a stub
    /// title with the resolved one once the topic finishes loading.
    func updateSocialTopicTitle(id: Int, title: String) {
        var mutated = false
        for i in stack.indices {
            if case let .socialTopic(topicId, existing) = stack[i], topicId == id, existing != title {
                stack[i] = .socialTopic(id: topicId, title: title)
                mutated = true
            }
        }
        if mutated { persist() }
    }

    @discardableResult
    func goBack() -> Entry? {
        guard canGoBack else { return nil }
        cursor -= 1
        persist()
        return stack[cursor]
    }

    @discardableResult
    func goForward() -> Entry? {
        guard canGoForward else { return nil }
        cursor += 1
        persist()
        return stack[cursor]
    }

    /// Runs the block with `isNavigating = true` — so consumers don't push
    /// back into history the changes that we ourselves initiated.
    func performNavigation(_ block: () -> Void) {
        isNavigating = true
        block()
        // Clear the flag on the next runloop tick: onChange subscribers will
        // already have reacted and checked the flag.
        DispatchQueue.main.async { [weak self] in
            self?.isNavigating = false
        }
    }

    // MARK: - Persistence

    private struct Persisted: Codable {
        var stack: [Entry]
        var cursor: Int
    }

    private func persist() {
        let payload = Persisted(stack: stack, cursor: cursor)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: persistKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: persistKey),
              let payload = try? JSONDecoder().decode(Persisted.self, from: data)
        else { return }
        // Sanitize in case the persisted cursor is out of bounds.
        let sanitizedCursor = max(-1, min(payload.cursor, payload.stack.count - 1))
        stack = payload.stack
        cursor = sanitizedCursor
    }
}

extension NavigationHistoryStore.Entry {
    /// Title for the hover tooltip: for a tab — its name, for a card — the
    /// anime title (or a placeholder while loading).
    var tooltipTitle: String {
        switch self {
        case .branch(let branch):       return branch.title
        case .detail(_, let title):     return title ?? "Загрузка…"
        case .socialTab(let tab):       return "Лента · \(tab.title)"
        case .socialTopic(_, let title): return title ?? "Обсуждение"
        }
    }
}
