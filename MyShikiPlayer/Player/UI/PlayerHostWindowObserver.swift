//
//  PlayerHostWindowObserver.swift
//  MyShikiPlayer
//

import AppKit
import SwiftUI

struct PlayerHostWindowObserver: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void
    var onKeyStatus: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ObserverView()
        view.onWindow = onWindow
        view.onKeyStatus = onKeyStatus
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ObserverView else { return }
        view.onWindow = onWindow
        view.onKeyStatus = onKeyStatus
    }

    final class ObserverView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        var onKeyStatus: ((Bool) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            onWindow?(window)
            guard let window else {
                onKeyStatus?(false)
                return
            }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyChanged),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyChanged),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
            keyChanged()
        }

        @objc private func keyChanged() {
            onKeyStatus?(window?.isKeyWindow == true)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
