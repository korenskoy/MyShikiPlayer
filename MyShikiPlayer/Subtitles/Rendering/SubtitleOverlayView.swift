//
//  SubtitleOverlayView.swift
//  MyShikiPlayer
//

import SwiftUI

/// Composer that selects and presents the correct subtitle renderer based on current state.
/// No side effects — all branching is pure derivation from observable inputs.
struct SubtitleOverlayView: View {
  @ObservedObject var engine: PlayerEngine
  let store: SubtitleStore
  let settings: SubtitleSettings

  // MARK: - Renderer identity

  private enum RendererKind: Equatable {
    case none
    case studio
    case custom
  }

  private var activeRenderer: RendererKind {
    guard let track = store.selectedTrack else { return .none }
    if track.assURL != nil && store.loadedAssBytes != nil && settings.useStudioStyle {
      return .studio
    }
    return .custom
  }

  // MARK: - Body

  var body: some View {
    ZStack {
      switch activeRenderer {
      case .none:
        EmptyView()
      case .studio:
        StudioSubtitleRenderer(engine: engine, store: store)
          .transition(.opacity)
          .id("studio")
      case .custom:
        CustomSubtitleRenderer(engine: engine, store: store, settings: settings)
          .transition(.opacity)
          .id("custom")
      }
    }
    .animation(.easeInOut(duration: 0.15), value: activeRenderer)
    .allowsHitTesting(false)
  }
}
