//
//  StudioSubtitleRenderer.swift
//  MyShikiPlayer
//

import AppKit
import Combine
import SwiftAssRenderer
import SwiftUI

/// libass-based renderer. Displays ASS/SSA subtitle tracks with full studio styling.
/// Wraps AssSubtitlesView (NSView) from swift-ass-renderer.
/// One AssSubtitlesRenderer instance per Coordinator lifetime; no global singleton needed
/// because libass per-instance state is cheap and isolated.
struct StudioSubtitleRenderer: NSViewRepresentable {
  @ObservedObject var engine: PlayerEngine
  let store: SubtitleStore

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> NSView {
    let container = FlippedView()
    container.wantsLayer = true
    container.layer?.backgroundColor = NSColor.clear.cgColor

    let subtitlesView = context.coordinator.subtitlesView
    subtitlesView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(subtitlesView)
    NSLayoutConstraint.activate([
      subtitlesView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      subtitlesView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      subtitlesView.topAnchor.constraint(equalTo: container.topAnchor),
      subtitlesView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    ])

    return container
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    // Reload track content when ASS bytes change.
    let bytes = store.loadedAssBytes
    if context.coordinator.loadedTrackID != store.selectedTrack?.id {
      context.coordinator.loadedTrackID = store.selectedTrack?.id
      if let data = bytes, let content = String(data: data, encoding: .utf8) {
        context.coordinator.renderer.loadTrack(content: content)
      } else {
        context.coordinator.renderer.freeTrack()
      }
    }

    // Push current adjusted time offset into the renderer.
    let adjustedTime = store.adjustedTime(forVideoTime: engine.currentTime)
    context.coordinator.renderer.setTimeOffset(adjustedTime)
  }

  static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
    coordinator.renderer.freeTrack()
    coordinator.cancellables.removeAll()
  }

  // MARK: - Coordinator

  @MainActor
  final class Coordinator {
    let renderer: AssSubtitlesRenderer
    let subtitlesView: AssSubtitlesView
    var cancellables = Set<AnyCancellable>()
    // Tracks which track ID has been loaded to avoid redundant loadTrack calls.
    var loadedTrackID: Int?

    init() {
      let fontsURL = Bundle.main.resourceURL ?? URL(fileURLWithPath: NSTemporaryDirectory())
      let config = FontConfig(
        fontsPath: fontsURL,
        defaultFontFamily: "Helvetica",
        fontProvider: .coreText
      )
      self.renderer = AssSubtitlesRenderer(fontConfig: config)
      self.subtitlesView = AssSubtitlesView(renderer: renderer)
    }
  }
}

// MARK: - FlippedView

/// NSView subclass with flipped coordinate system to match SwiftUI's top-left origin.
private final class FlippedView: NSView {
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
