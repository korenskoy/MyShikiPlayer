//
//  Wordmark.swift
//  MyShikiPlayer
//
//  App logo + the "myshiki." wordmark and tagline.
//  The logo is the app icon from Assets.xcassets/AppIcon.appiconset
//  (macOS hands back the right resolution via NSApp.applicationIconImage).
//

import AppKit
import SwiftUI

struct BrandLogo: View {
    @Environment(\.appTheme) private var theme
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let icon = NSApp?.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                // Fallback for previews and edge cases when NSApp isn't ready yet.
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(theme.accent)
            }
        }
        .frame(width: size, height: size)
    }
}

struct Wordmark: View {
    @Environment(\.appTheme) private var theme
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            BrandLogo(size: compact ? 28 : 34)
            if !compact {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 0) {
                        Text("myshiki")
                            .font(.dsTitle(16, weight: .heavy))
                            .foregroundStyle(theme.fg)
                        Text(".")
                            .font(.dsTitle(16, weight: .heavy))
                            .foregroundStyle(theme.accent)
                    }
                    .tracking(-0.3)

                    Text("КАТАЛОГ + ПЛЕЕР")
                        .font(.dsLabel(8))
                        .tracking(1.5)
                        .foregroundStyle(theme.fg3)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Paper") {
    VStack(spacing: 20) {
        Wordmark()
        Wordmark(compact: true)
    }
    .padding(24)
    .background(AppTheme.paper.bg)
    .appTheme(.paper)
}
#endif
