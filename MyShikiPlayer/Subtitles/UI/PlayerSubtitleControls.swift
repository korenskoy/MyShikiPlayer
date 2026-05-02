//
//  PlayerSubtitleControls.swift
//  MyShikiPlayer
//
//  CC button and its popover. Lives in the player bottom bar.
//  Tracks are never loaded automatically — the user must tap "Найти субтитры".
//

import SwiftUI

struct PlayerSubtitleControls: View {
  @ObservedObject var engine: PlayerEngine
  @Environment(\.subtitlesAssembly) private var assemblyOrNil

  @State private var isPopoverShown = false
  @State private var hasRequestedTracks = false

  private var store: SubtitleStore { assemblyOrNil!.store }
  private var settings: SubtitleSettings { assemblyOrNil!.settings }

  var body: some View {
    if assemblyOrNil != nil {
      DSPlayerIconButton(icon: .cc) {
        isPopoverShown.toggle()
      }
      .popover(isPresented: $isPopoverShown, arrowEdge: .top) {
        popoverContent
      }
    }
  }

  // MARK: - Popover

  /// Fixed height of the scrollable list region. Picked to fit ~16 rows
  /// without making the popover taller than a typical short window.
  private static let listHeight: CGFloat = 480
  /// Compact width for transient states (loading / find / error / empty).
  private static let compactWidth: CGFloat = 280
  /// Comfortable width for the loaded track list — fits longer studio names.
  private static let expandedWidth: CGFloat = 380

  private var popoverContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
        .background(Color.white.opacity(0.08))

      bodyRegion

      if showsOffsetBar {
        Divider()
          .background(Color.white.opacity(0.08))
        SubtitleOffsetControls(store: store, disabled: store.selectedTrack == nil)
          .padding(.horizontal, 6)
          .padding(.vertical, 8)
      }
    }
    .frame(width: showsOffsetBar ? Self.expandedWidth : Self.compactWidth)
    .background(Color(hex: 0x141218))
  }

  private var header: some View {
    Text("Субтитры")
      .font(.dsMono(10, weight: .semibold))
      .tracking(1.2)
      .foregroundStyle(Color.white.opacity(0.5))
      .padding(.horizontal, 14)
      .padding(.top, 12)
      .padding(.bottom, 10)
  }

  /// Contents below the sticky header. The track list is wrapped in a ScrollView
  /// with a fixed height; transient states (loading / empty / error) stay flat.
  @ViewBuilder
  private var bodyRegion: some View {
    if store.availableTracks.isEmpty {
      transientContent
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    } else {
      ScrollView(.vertical, showsIndicators: true) {
        SubtitleTrackPicker(
          store: store,
          preferredLanguage: settings.resolvedLanguage
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
      }
      .frame(height: Self.listHeight)
    }
  }

  @ViewBuilder
  private var transientContent: some View {
    if store.isLoadingTracks {
      loadingView
    } else if let errorMsg = store.errorMessage {
      errorView(errorMsg)
    } else if hasRequestedTracks {
      unavailableView
    } else {
      findButton
    }
  }

  /// Offset bar is shown only when there is at least one track available.
  private var showsOffsetBar: Bool {
    !store.isLoadingTracks
      && store.errorMessage == nil
      && !store.availableTracks.isEmpty
  }

  private var loadingView: some View {
    HStack(spacing: 10) {
      ProgressView()
        .controlSize(.small)
        .tint(.white)
      Text("Загрузка треков…")
        .font(.dsBody(12, weight: .regular))
        .foregroundStyle(Color.white.opacity(0.6))
    }
    .frame(maxWidth: .infinity, alignment: .center)
    .padding(.vertical, 24)
  }

  private func errorView(_ message: String) -> some View {
    VStack(spacing: 10) {
      Text(message)
        .font(.dsBody(11, weight: .regular))
        .foregroundStyle(Color(hex: 0xFF4D5E))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)
      Button("Повторить") {
        Task {
          hasRequestedTracks = true
          await store.requestTracks()
          autoSelectPreferredTrack()
        }
      }
      .font(.dsBody(11, weight: .semibold))
      .foregroundStyle(Color.white)
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
  }

  private var unavailableView: some View {
    Text("Субтитры недоступны для этого эпизода")
      .font(.dsBody(11, weight: .regular))
      .foregroundStyle(Color.white.opacity(0.5))
      .multilineTextAlignment(.center)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 24)
      .padding(.horizontal, 8)
  }

  private var findButton: some View {
    Button {
      Task {
        hasRequestedTracks = true
        await store.requestTracks()
        autoSelectPreferredTrack()
      }
    } label: {
      Text("Найти субтитры")
        .font(.dsBody(12, weight: .semibold))
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(hex: 0xFF4D5E))
        )
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 8)
    .padding(.vertical, 16)
  }

  // MARK: - Auto-select

  private func autoSelectPreferredTrack() {
    guard store.selectedTrack == nil else { return }
    guard let targetLang = settings.resolvedLanguage else { return }
    guard let match = store.availableTracks.first(where: { $0.language == targetLang }) else { return }
    Task { await store.selectTrack(match) }
  }
}
