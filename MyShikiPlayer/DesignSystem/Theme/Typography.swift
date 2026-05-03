//
//  Typography.swift
//  MyShikiPlayer
//
//  System-first font set per the design-reference spec.
//  Unbounded -> SF Pro Rounded Heavy/Bold        (display / titles)
//  Manrope   -> SF Pro (system default)          (body)
//  Small UPPERCASE / kicker / romaji / badge   ->
//          system-ui / SF Pro Text (NOT monospaced — design ref dropped mono)
//  Real monospace is only for timecode and other technical content
//  via `dsTimecode(size:)` or `Font.dsTechMono(...)`.
//
//  If we miss the visual target significantly, drop Unbounded-Variable.ttf
//  and Manrope-Variable.ttf into Resources/Fonts/ and reroute dsDisplay /
//  dsTitle / dsBody to Font.custom — the component interface will not change.
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

    /// Body text (Manrope → SF Pro)
    static func dsBody(_ size: CGFloat = 14, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Small UI label / kicker / romaji / breadcrumb. Sans (system-ui),
    /// not monospaced. Pair with `.tracking()` and `.textCase(.uppercase)`
    /// when the role calls for it.
    static func dsMono(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }

    /// Short uppercase label like "DUB", "SUB", "PREVIEW". Sans.
    static func dsLabel(_ size: CGFloat = 10, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight)
    }

    /// Real monospace for technical content: timecode, byte sizes, host:port.
    /// Distinct from `dsMono` — that one is sans despite the legacy name.
    static func dsTechMono(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Typography modifiers (to keep call sites concise)

extension Text {
    /// Uppercase sans label with letter-tracking. For "EP 07 · ROMAJI" etc.
    /// Despite the legacy name, this is no longer monospaced (design ref switched
    /// these labels to system-ui / SF Pro Text).
    func dsMonoLabel(size: CGFloat = 10, tracking: CGFloat = 1.5) -> some View {
        self
            .font(.dsLabel(size))
            .tracking(tracking)
            .textCase(.uppercase)
    }

    /// Timecode: real monospace, no uppercase, standard tracking.
    func dsTimecode(size: CGFloat = 12) -> some View {
        self
            .font(.dsTechMono(size, weight: .semibold))
    }
}
