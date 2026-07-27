//
//  PlayerWindowCoordinator.swift
//  MyShikiPlayer
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class PlayerWindowCoordinator: NSObject {
    private var playerWindow: NSWindow?
    private var currentSession: PlaybackSession?
    private var onClose: (() -> Void)?
    private var sessionObserver: AnyCancellable?

    /// Opens the player. `windowWillClose` drops `playerWindow`, so every open
    /// after a close builds a fresh NSWindow — the reuse branch below only
    /// covers picking another episode / title while the window is still up
    /// (the SwiftUI root view is swapped in place, so PlayerView is updated,
    /// not re-created).
    func open(session: PlaybackSession, onClose: @escaping () -> Void) {
        self.onClose = onClose

        if let playerWindow {
            currentSession = session
            if let hosting = playerWindow.contentViewController as? NSHostingController<PlayerView> {
                hosting.rootView = PlayerView(session: session) { [weak self] in
                    self?.closeWindow()
                }
            }
            bindWindowTitle(to: session)
            playerWindow.title = makeWindowTitle(for: session)
            playerWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        currentSession = session
        let rootView = PlayerView(session: session) { [weak self] in
            self?.closeWindow()
        }
        let hosting = NSHostingController(rootView: rootView)

        let window = NSWindow(contentViewController: hosting)
        window.title = makeWindowTitle(for: session)
        window.minSize = NSSize(width: 960, height: 620)
        window.setContentSize(NSSize(width: 1280, height: 800))
        window.styleMask.insert(.resizable)
        window.styleMask.insert(.miniaturizable)
        window.styleMask.insert(.closable)
        // Cinema look: video fills under the title bar so there is no grey /
        // accent strip at the top. Traffic-light buttons keep floating over the
        // video; the overlay draws its own back/pin controls and title.
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // The coordinator holds the window strongly, so AppKit must not release
        // it on close as well — that is an over-release under ARC, not a reuse
        // mechanism. The reference is dropped in `windowWillClose`.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        playerWindow = window
        bindWindowTitle(to: session)
    }

    private func closeWindow() {
        playerWindow?.close()
    }
}

extension PlayerWindowCoordinator: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        currentSession?.saveProgressSnapshot()
        onClose?()
        sessionObserver?.cancel()
        sessionObserver = nil
        playerWindow = nil
        currentSession = nil
    }
}

private extension PlayerWindowCoordinator {
    func bindWindowTitle(to session: PlaybackSession) {
        sessionObserver?.cancel()
        sessionObserver = session.$selectedSource
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, let playerWindow = self.playerWindow else { return }
                playerWindow.title = self.makeWindowTitle(for: session)
            }
    }

    func makeWindowTitle(for session: PlaybackSession) -> String {
        if let selectedSource = session.selectedSource {
            return "\(selectedSource.title) - серия \(selectedSource.episode)"
        }
        return "Плеер"
    }
}
