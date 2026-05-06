//
//  PlayerEngine.swift
//  MyShikiPlayer
//

import AppKit
import AVKit
import Combine
import Foundation

@MainActor
final class PlayerEngine: ObservableObject {
    private enum PersistedKey {
        static let volume = "player.volume"
        static let playbackRate = "player.playbackRate"
    }

    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var canStartPlayback = false
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var playbackRate: Float = 1.0
    @Published var volume: Float = 0.8
    @Published private(set) var lastLoadError: String?

    let player: AVPlayer = AVPlayer()

    private var timeObserver: Any?
    private var cancellables: Set<AnyCancellable> = []
    private var itemCancellables: Set<AnyCancellable> = []
    private var autoplayPending = false
    private var pendingSeekSeconds: Double?
    private weak var hostWindow: NSWindow?
    /// Window hosting the player sheet; used for autoplay, key-window and fullscreen logic.
    var playerHostWindow: NSWindow? { hostWindow }
    private var keyWindowObservers: [NSObjectProtocol] = []
    private var appBecameActiveObserver: NSObjectProtocol?

    init() {
        volume = Self.loadPersistedVolume()
        playbackRate = Self.loadPersistedPlaybackRate()
        player.volume = volume
        configureBindings()
        addPeriodicTimeObserver()
        appBecameActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tryFulfillPendingAutoplay()
            }
        }
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        if let appBecameActiveObserver {
            NotificationCenter.default.removeObserver(appBecameActiveObserver)
        }
        // Window-key observers are added in `setHostWindow` and only cleared
        // there on a fresh call. If the engine is released without a final
        // `setHostWindow(nil)` (typical when the player sheet collapses), the
        // tokens would leak inside NotificationCenter.
        for observer in keyWindowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Deferred autoplay only when this process is active and the player’s window is key (never when `hostWindow` is unset).
    private var allowsDeferredAutoplay: Bool {
        guard let hostWindow else { return false }
        return NSApp.isActive && hostWindow.isKeyWindow
    }

    func load(url: URL, autoPlay: Bool) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        isBuffering = true
        lastLoadError = nil
        autoplayPending = autoPlay
        pendingSeekSeconds = nil
        if autoPlay {
            tryFulfillPendingAutoplay()
        }
    }

    /// Host window for gating automatic playback from `load(..., autoPlay: true)` until the player is key.
    func setHostWindow(_ window: NSWindow?) {
        for observer in keyWindowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        keyWindowObservers.removeAll()
        hostWindow = window
        guard let window else { return }
        window.collectionBehavior.insert(.fullScreenPrimary)
        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tryFulfillPendingAutoplay()
            }
        }
        keyWindowObservers.append(token)
        tryFulfillPendingAutoplay()
    }

    func tryFulfillPendingAutoplay() {
        guard autoplayPending, allowsDeferredAutoplay else { return }
        play()
    }

    /// Toggle fullscreen for the player window (no fallback to `NSApp.keyWindow`).
    func togglePlayerWindowFullScreen() {
        guard let window = playerHostWindow else { return }
        window.toggleFullScreen(nil)
    }

    func play() {
        autoplayPending = false
        player.play()
        player.rate = playbackRate
        isPlaying = true
    }

    func pause() {
        autoplayPending = false
        player.pause()
        isPlaying = false
    }

    func stopAndUnload() {
        autoplayPending = false
        pendingSeekSeconds = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        isBuffering = false
        canStartPlayback = false
        currentTime = 0
        duration = 0
    }

    func playOrPause() {
        isPlaying ? pause() : play()
    }

    func seek(seconds: Double) {
        let requested = max(0, seconds)
        let target = duration > 0 ? min(duration, requested) : requested
        guard target.isFinite else { return }
        isBuffering = true
        guard canStartPlayback else {
            pendingSeekSeconds = target
            return
        }
        applySeek(seconds: target)
    }

    func seek(delta: Double) {
        seek(seconds: currentTime + delta)
    }

    private func configureBindings() {
        NotificationCenter.default.publisher(for: .AVPlayerItemFailedToPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self else { return }
                if let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError {
                    self.lastLoadError = error.localizedDescription
                } else {
                    self.lastLoadError = "Playback failed to end"
                }
                self.isPlaying = false
            }
            .store(in: &cancellables)

        player.publisher(for: \.currentItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] item in
                self?.bindCurrentItem(item)
            }
            .store(in: &cancellables)

        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.isBuffering = status == .waitingToPlayAtSpecifiedRate
                self.isPlaying = status == .playing
            }
            .store(in: &cancellables)

        $playbackRate
            .dropFirst()
            .sink { [weak self] rate in
                UserDefaults.standard.set(Double(rate), forKey: PersistedKey.playbackRate)
                guard let self, self.isPlaying else { return }
                self.player.rate = rate
            }
            .store(in: &cancellables)

        $volume
            .dropFirst()
            .sink { [weak self] value in
                let clamped = max(0.0, min(1.0, value))
                self?.player.volume = clamped
                UserDefaults.standard.set(clamped, forKey: PersistedKey.volume)
            }
            .store(in: &cancellables)
    }

    private static func loadPersistedVolume() -> Float {
        let stored = UserDefaults.standard.object(forKey: PersistedKey.volume) as? Double
        guard let stored else { return 0.8 }
        return Float(max(0.0, min(1.0, stored)))
    }

    private static func loadPersistedPlaybackRate() -> Float {
        let stored = UserDefaults.standard.object(forKey: PersistedKey.playbackRate) as? Double
        guard let stored else { return 1.0 }
        // Clamp to the picker's supported range so a stale or hand-edited
        // preference can never put the player into an unreachable state.
        return Float(max(0.5, min(2.0, stored)))
    }

    private func applySeek(seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            guard let self else { return }
            self.pendingSeekSeconds = nil
            if self.player.timeControlStatus != .waitingToPlayAtSpecifiedRate {
                self.isBuffering = false
            }
        }
    }

    private func addPeriodicTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            self.currentTime = time.seconds.isFinite ? time.seconds : 0
            if let item = self.player.currentItem {
                let seconds = item.duration.seconds
                self.duration = seconds.isFinite ? seconds : 0
            }
        }
    }

    private func bindCurrentItem(_ item: AVPlayerItem?) {
        itemCancellables.removeAll()
        canStartPlayback = false
        // Wipe any error left over from the previous item so a delayed
        // `.failed` from the OLD AVPlayerItem (it may publish status after we
        // already replaced `currentItem`) cannot stick to the freshly-loaded
        // URL. The identity guard below additionally protects the publisher
        // path from cross-item leakage.
        lastLoadError = nil
        guard let item else { return }

        item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                // Reject late events from a stale AVPlayerItem — by the time
                // its status finally reaches `.failed`, the player is already
                // serving a different URL.
                guard self.player.currentItem === item else { return }
                self.canStartPlayback = status == .readyToPlay
                if status == .readyToPlay {
                    if let pendingSeekSeconds = self.pendingSeekSeconds {
                        self.applySeek(seconds: pendingSeekSeconds)
                    }
                    self.tryFulfillPendingAutoplay()
                }
                if status == .failed {
                    self.lastLoadError = item.error?.localizedDescription ?? "Failed to load media item"
                    self.isPlaying = false
                }
            }
            .store(in: &itemCancellables)

        NotificationCenter.default.publisher(for: .AVPlayerItemPlaybackStalled, object: item)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isBuffering = true
            }
            .store(in: &itemCancellables)
    }
}
