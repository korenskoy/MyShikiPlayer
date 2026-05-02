//
//  PlayerView.swift
//
//  Root view of the player window. A thin layer on top of ClassicPlayerOverlay:
//  - keeps AVPlayerView in the background,
//  - manages overlay visibility (hover + opacity-based auto-hide),
//  - autoplay after the app/window becomes active,
//  - keyboard shortcuts via PlayerShortcuts,
//  - PlayerHostWindowObserver to bind the NSWindow to the engine.
//

import AppKit
import Combine
import SwiftUI

struct PlayerView: View {
    @ObservedObject var session: PlaybackSession
    @Environment(\.dismiss) private var dismiss
    let onRequestClose: (() -> Void)?

    @State private var isOverlayVisible = true
    @State private var autoHideTask: Task<Void, Never>?
    @State private var playerWindowIsKey = false
    @State private var appIsActive = NSApp.isActive
    @State private var didInitialAutostart = false
    @State private var subtitlesAssembly = SubtitlesAssembly()
    @State private var subtitlesCancellable: AnyCancellable?
    @AppStorage("player.alwaysOnTop") private var alwaysOnTop: Bool = false

    init(session: PlaybackSession, onRequestClose: (() -> Void)? = nil) {
        self.session = session
        self.onRequestClose = onRequestClose
    }

    var body: some View {
        ZStack {
            videoLayer

            SubtitleOverlayView(
                engine: session.engine,
                store: subtitlesAssembly.store,
                settings: subtitlesAssembly.settings
            )

            ClassicPlayerOverlay(
                session: session,
                engine: session.engine,
                isVisible: isOverlayVisible,
                isAlwaysOnTop: alwaysOnTop,
                onRequestClose: requestClose,
                onToggleAlwaysOnTop: { alwaysOnTop.toggle() }
            )

            if session.isPreparing || session.engine.isBuffering {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .environment(\.subtitlesAssembly, subtitlesAssembly)
        .playerShortcuts(session: session) {
            requestClose()
        }
        .background(
            PlayerHostWindowObserver(
                onWindow: { window in
                    session.engine.setHostWindow(window)
                    applyAlwaysOnTop(alwaysOnTop, to: window)
                },
                onKeyStatus: { playerWindowIsKey = $0 }
            )
        )
        .onChange(of: alwaysOnTop) { _, on in
            applyAlwaysOnTop(on, to: session.engine.playerHostWindow)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            // macOS forces .normal level when entering fullscreen and does
            // NOT restore custom levels on exit — reapply the user's choice.
            guard let window = note.object as? NSWindow,
                  window === session.engine.playerHostWindow else { return }
            applyAlwaysOnTop(alwaysOnTop, to: window)
        }
        .onAppear {
            appIsActive = NSApp.isActive
            revealOverlayAndScheduleHide()
            subtitlesCancellable = subtitlesAssembly.store.attach(to: session)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appIsActive = true
            attemptAutostartWhenForeground()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            appIsActive = false
        }
        .onChange(of: playerWindowIsKey) { _, isKey in
            if isKey {
                attemptAutostartWhenForeground()
            }
        }
        .onChange(of: session.engine.canStartPlayback) { _, ready in
            if ready {
                attemptAutostartWhenForeground()
            }
        }
        .onChange(of: session.engine.isPlaying) { _, isPlaying in
            if isPlaying {
                scheduleAutoHideIfNeeded()
            } else {
                cancelAutoHide()
                revealOverlay()
            }
        }
        .onChange(of: session.engine.isBuffering) { _, isBuffering in
            if isBuffering {
                cancelAutoHide()
            } else {
                scheduleAutoHideIfNeeded()
            }
        }
        .onDisappear {
            cancelAutoHide()
            subtitlesCancellable = nil
            // The PlayerWindowCoordinator reuses the same NSWindow across
            // opens (`isReleasedWhenClosed = false`), so leaving the level
            // at `.floating` would leak the pin into the next session
            // before `onWindow` reapplies the user's stored choice. Reset.
            session.engine.playerHostWindow?.level = .normal
            // Save the position BEFORE stopAndUnload — otherwise it will reset
            // engine.currentTime to 0, and progressStore will write a zero
            // position, overwriting the correct entry from windowWillClose.
            session.saveProgressSnapshot()
            session.engine.stopAndUnload()
        }
        .frame(minWidth: 1200, minHeight: 760)
    }

    /// Background layer: video + tap for pause/play + hover trigger.
    private var videoLayer: some View {
        PlayerContainerView(player: session.engine.player)
            .background(Color.black)
            .ignoresSafeArea()
            .onTapGesture {
                session.engine.playOrPause()
                revealOverlayAndScheduleHide()
            }
            .onHover { hovering in
                guard hovering else { return }
                revealOverlayAndScheduleHide()
            }
            .onContinuousHover { phase in
                if case .active = phase {
                    revealOverlayAndScheduleHide()
                }
            }
    }

    private func requestClose() {
        if let onRequestClose {
            // Do not call stopAndUnload before the window closes: windowWillClose
            // invokes syncProgressFromPlayback which needs the live currentTime/duration.
            onRequestClose()
        } else {
            session.engine.stopAndUnload()
            dismiss()
        }
    }

    private func attemptAutostartWhenForeground() {
        guard appIsActive, playerWindowIsKey else { return }
        guard !didInitialAutostart else { return }
        session.engine.tryFulfillPendingAutoplay()
        if session.engine.isPlaying {
            didInitialAutostart = true
            return
        }
        guard session.engine.canStartPlayback else { return }
        session.engine.play()
        didInitialAutostart = true
    }

    private func revealOverlay() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isOverlayVisible = true
        }
    }

    private func revealOverlayAndScheduleHide() {
        revealOverlay()
        scheduleAutoHideIfNeeded()
    }

    private func scheduleAutoHideIfNeeded() {
        cancelAutoHide()
        guard session.engine.isPlaying, !session.engine.isBuffering, !session.isPreparing else { return }
        autoHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, session.engine.isPlaying else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                isOverlayVisible = false
            }
        }
    }

    private func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    /// Pin/unpin the player window above other apps.
    /// Uses `.floating` (not `.modalPanel` / `.popUpMenu`) so the window can
    /// still be moved, resized, focus other windows, and enter fullscreen.
    private func applyAlwaysOnTop(_ on: Bool, to window: NSWindow?) {
        guard let window else { return }
        window.level = on ? .floating : .normal
    }
}
