//
//  ImageLightbox.swift
//  MyShikiPlayer
//
//  Full-screen screenshot viewer overlaid on AnimeDetailsView. Background is
//  a dimmer; click outside the image / Esc closes; ← / → keys paginate.
//

import AppKit
import SwiftUI

struct ImageLightbox: View {
    @Environment(\.appTheme) private var theme
    let urls: [URL]
    @Binding var selectedIndex: Int?
    @FocusState private var focused: Bool

    private func goPrevious() {
        guard let idx = selectedIndex, idx > 0 else { return }
        selectedIndex = idx - 1
    }

    private func goNext() {
        guard let idx = selectedIndex, idx < urls.count - 1 else { return }
        selectedIndex = idx + 1
    }

    var body: some View {
        if let index = selectedIndex, urls.indices.contains(index) {
            ZStack {
                Color.black.opacity(0.88).ignoresSafeArea()
                    .onTapGesture { selectedIndex = nil }

                CachedRemoteImage(
                    url: urls[index],
                    contentMode: .fit,
                    placeholder: { ProgressView().controlSize(.large).tint(.white) },
                    failure: {
                        VStack(spacing: 8) {
                            DSIcon(name: .xmark, size: 22, weight: .bold)
                                .foregroundStyle(Color.white.opacity(0.7))
                            Text("Не удалось загрузить")
                                .font(.dsBody(13))
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
                )
                .padding(48)

                VStack {
                    HStack {
                        Spacer()
                        Button {
                            selectedIndex = nil
                        } label: {
                            DSIcon(name: .xmark, size: 20, weight: .bold)
                                .foregroundStyle(Color.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle().fill(Color.white.opacity(0.15))
                                        .background(.ultraThinMaterial, in: Circle())
                                )
                        }
                        .buttonStyle(.plain)
                        .padding(16)
                        .keyboardShortcut(.cancelAction)
                    }
                    Spacer()
                    if urls.count > 1 {
                        HStack {
                            navButton(icon: .chevL, disabled: index == 0, action: goPrevious)
                            Spacer()
                            Text("\(index + 1) / \(urls.count)")
                                .font(.dsMono(12, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.7))
                            Spacer()
                            navButton(icon: .chevR, disabled: index >= urls.count - 1, action: goNext)
                        }
                        .padding(20)
                    }
                }
            }
            .transition(.opacity)
            .zIndex(100)
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onAppear { focused = true }
            .onChange(of: selectedIndex) { _, newValue in
                // Restore focus if within the same session the user clicked
                // with the mouse — after that, keypresses could have lost focus.
                if newValue != nil { focused = true }
            }
            .onKeyPress(.leftArrow) {
                goPrevious()
                return .handled
            }
            .onKeyPress(.rightArrow) {
                goNext()
                return .handled
            }
            .onKeyPress(.escape) {
                selectedIndex = nil
                return .handled
            }
        }
    }

    private func navButton(icon: DSIconName, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            DSIcon(name: icon, size: 18, weight: .bold)
                .foregroundStyle(Color.white.opacity(disabled ? 0.3 : 1))
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(Color.white.opacity(0.15))
                        .background(.ultraThinMaterial, in: Circle())
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
