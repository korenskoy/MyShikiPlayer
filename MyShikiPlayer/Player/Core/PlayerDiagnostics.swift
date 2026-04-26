//
//  PlayerDiagnostics.swift
//  MyShikiPlayer
//

import Foundation
import Combine

@MainActor
final class PlayerDiagnostics: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    func log(_ message: String) {
        entries.append(Entry(message: message))
        if entries.count > 500 {
            entries.removeFirst(entries.count - 500)
        }
    }

    func clear() {
        entries.removeAll()
    }
}
