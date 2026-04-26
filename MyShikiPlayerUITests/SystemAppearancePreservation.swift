//
//  SystemAppearancePreservation.swift
//  MyShikiPlayerUITests
//
//  Saves NSGlobalDomain AppleInterfaceStyle before the UI test bundle runs and restores it in testBundleDidFinish.
//

import Foundation
import XCTest

/// Snapshot of `defaults read -g AppleInterfaceStyle` (Dark / Light / absent ≈ Auto or system Light).
private enum AppearanceSnapshot: Equatable {
    case absent
    case dark
    case light
}

private enum DefaultsGlobalAppearance {
    private static let executable = URL(fileURLWithPath: "/usr/bin/defaults")

    static func readInterfaceStyle() -> AppearanceSnapshot {
        let (code, output) = run(arguments: ["read", "-g", "AppleInterfaceStyle"])
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if code != 0 || trimmed.isEmpty { return .absent }
        if trimmed == "Dark" { return .dark }
        if trimmed == "Light" { return .light }
        return .absent
    }

    static func apply(_ snapshot: AppearanceSnapshot) {
        switch snapshot {
        case .absent:
            _ = run(arguments: ["delete", "-g", "AppleInterfaceStyle"])
        case .dark:
            _ = run(arguments: ["write", "-g", "AppleInterfaceStyle", "Dark"])
        case .light:
            _ = run(arguments: ["write", "-g", "AppleInterfaceStyle", "Light"])
        }
    }

    private static func run(arguments: [String]) -> (status: Int32, output: String) {
        let task = Process()
        task.executableURL = executable
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return (-1, "")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return (task.terminationStatus, text)
    }
}

/// Observes the UI test bundle and restores system appearance after Xcode runs multi-appearance launch tests.
final class SystemAppearancePreservation: NSObject, XCTestObservation {
    static let shared = SystemAppearancePreservation()
    private static var didRegister = false

    private var snapshot: AppearanceSnapshot = .absent

    private override init() {
        super.init()
    }

    static func registerIfNeeded() {
        guard !didRegister else { return }
        didRegister = true
        XCTestObservationCenter.shared.addTestObserver(shared)
    }

    func testBundleWillStart(_ testBundle: Bundle) {
        snapshot = DefaultsGlobalAppearance.readInterfaceStyle()
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        DefaultsGlobalAppearance.apply(snapshot)
    }
}
