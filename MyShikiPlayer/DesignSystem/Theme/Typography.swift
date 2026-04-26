//
//  Typography.swift
//  MyShikiPlayer
//
//  System-first font set per the design-reference spec.
//  Unbounded  -> SF Pro Rounded Heavy    (display / titles)
//  Manrope    -> SF Pro (system default) (body)
//  JBMono     -> SF Mono (system)        (timecode / tech labels)
//
//  If we miss the visual target significantly, add Unbounded-Variable.ttf to Resources/Fonts/
//  and reroute dsDisplay there — the component interface will not change.
//

import SwiftUI

extension Font {
    /// Display / large headings (Unbounded → SF Pro Rounded Heavy)
    static func dsDisplay(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Regular heading (Unbounded Bold)
    static func dsTitle(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Body text (Manrope)
    static func dsBody(_ size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Mono labels: timecode, EP 07, ROMAJI labels. Wider tracking than normal — set on Text via .tracking().
    static func dsMono(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Short uppercase label: "DUB", "SUB", "PREVIEW". Typically 9–11pt.
    static func dsLabel(_ size: CGFloat = 10, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Typography modifiers (to keep call sites concise)

extension Text {
    /// Uppercase mono label with letter-tracking 1.5. For "EP 07 · ROMAJI" etc.
    func dsMonoLabel(size: CGFloat = 10, tracking: CGFloat = 1.5) -> some View {
        self
            .font(.dsLabel(size))
            .tracking(tracking)
            .textCase(.uppercase)
    }

    /// Timecode: mono, no uppercase, standard tracking.
    func dsTimecode(size: CGFloat = 12) -> some View {
        self
            .font(.dsMono(size, weight: .semibold))
    }
}
