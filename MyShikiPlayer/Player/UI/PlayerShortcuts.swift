//
//  PlayerShortcuts.swift
//  MyShikiPlayer
//

import SwiftUI
import AppKit

struct PlayerShortcuts: ViewModifier {
    @ObservedObject var session: PlaybackSession
    let dismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .focusable()
            .onExitCommand(perform: dismiss)
            .onMoveCommand { direction in
                switch direction {
                case .left:
                    session.engine.seek(delta: -10)
                case .right:
                    session.engine.seek(delta: 10)
                case .up:
                    session.engine.volume = min(1.0, session.engine.volume + 0.05)
                case .down:
                    session.engine.volume = max(0.0, session.engine.volume - 0.05)
                default:
                    break
                }
            }
            .onKeyPress(.init("f")) {
                session.engine.togglePlayerWindowFullScreen()
                return .handled
            }
            .onKeyPress(.space) {
                session.engine.playOrPause()
                return .handled
            }
            .onKeyPress(.init("s")) {
                guard let opening = session.currentOpeningRangeSeconds,
                      opening.lowerBound <= session.engine.currentTime,
                      session.engine.currentTime < opening.upperBound else {
                    return .ignored
                }
                let target = min(opening.upperBound, max(session.engine.duration - 1, 0))
                session.engine.seek(seconds: target)
                return .handled
            }
    }
}

extension View {
    func playerShortcuts(session: PlaybackSession, dismiss: @escaping () -> Void) -> some View {
        modifier(PlayerShortcuts(session: session, dismiss: dismiss))
    }
}
