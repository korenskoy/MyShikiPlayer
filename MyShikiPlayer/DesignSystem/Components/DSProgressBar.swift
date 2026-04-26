//
//  DSProgressBar.swift
//  MyShikiPlayer
//
//  Thin progress bar. Equivalent of ProgressBar from primitives.jsx.
//

import SwiftUI

struct DSProgressBar: View {
    @Environment(\.appTheme) private var theme

    /// 0.0 ... 1.0
    var value: Double
    var height: CGFloat = 3
    var trackColor: Color? = nil
    var fillColor: Color? = nil

    var body: some View {
        GeometryReader { geo in
            let clamped = max(0, min(1, value))
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(trackColor ?? theme.line)
                Capsule(style: .continuous)
                    .fill(fillColor ?? theme.accent)
                    .frame(width: geo.size.width * clamped)
                    .animation(.easeOut(duration: 0.25), value: clamped)
            }
        }
        .frame(height: height)
    }
}
