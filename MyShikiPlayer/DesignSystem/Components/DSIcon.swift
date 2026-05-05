//
//  DSIcon.swift
//  MyShikiPlayer
//
//  Bridge between icon names from the design (primitives.jsx → switch by name)
//  and SF Symbols. If the name is unknown, return questionmark.circle so the
//  gap in the design stays visible rather than invisible.
//

import SwiftUI

enum DSIconName: String, CaseIterable {
    case play, pause
    case search
    case bookmark
    case check
    case plus
    case xmark
    case chevL, chevR, chevD, chevU
    case settings, gear
    case home
    case grid
    case calendar
    case user, users
    case heart
    case star
    case cc
    case mic
    case vol
    case full
    case next
    case skip
    case skip10Back
    case skip10Forward
    case list
    case clock
    case fire
    case bell
    case link
    case safari
    case speed
    case pip
    case pin
    case pinFill
    case info
    case refresh
    case arrowUp

    /// SF Symbol used for this icon.
    var symbolName: String {
        switch self {
        case .play:      return "play.fill"
        case .pause:     return "pause.fill"
        case .search:    return "magnifyingglass"
        case .bookmark:  return "bookmark"
        case .check:     return "checkmark"
        case .plus:      return "plus"
        case .xmark:     return "xmark"
        case .chevL:     return "chevron.left"
        case .chevR:     return "chevron.right"
        case .chevD:     return "chevron.down"
        case .chevU:     return "chevron.up"
        case .settings:  return "gearshape"
        case .gear:      return "gearshape.fill"
        case .home:      return "house"
        case .grid:      return "square.grid.2x2"
        case .calendar:  return "calendar"
        case .user:      return "person"
        case .users:     return "person.2"
        case .heart:     return "heart"
        case .star:      return "star.fill"
        case .cc:        return "captions.bubble"
        case .mic:       return "mic"
        case .vol:       return "speaker.wave.2"
        case .full:      return "arrow.up.left.and.arrow.down.right"
        case .next:      return "forward.end.fill"
        case .skip:      return "forward.fill"
        case .skip10Back:    return "gobackward.10"
        case .skip10Forward: return "goforward.10"
        case .list:      return "list.bullet"
        case .clock:     return "clock"
        case .fire:      return "flame"
        case .bell:      return "bell"
        case .link:      return "link"
        case .safari:    return "safari"
        case .speed:     return "gauge.with.dots.needle.50percent"
        case .pip:       return "pip.enter"
        case .pin:       return "pin"
        case .pinFill:   return "pin.fill"
        case .info:      return "info.circle"
        case .refresh:   return "arrow.clockwise"
        case .arrowUp:   return "arrow.up"
        }
    }
}

struct DSIcon: View {
    let name: DSIconName
    var size: CGFloat = 16
    var weight: Font.Weight = .medium

    var body: some View {
        Image(systemName: name.symbolName)
            .font(.system(size: size, weight: weight))
            .symbolRenderingMode(.monochrome)
    }
}

#if DEBUG
#Preview("Icon grid") {
    let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 6)
    return LazyVGrid(columns: columns, spacing: 16) {
        ForEach(DSIconName.allCases, id: \.self) { n in
            VStack(spacing: 4) {
                DSIcon(name: n, size: 18)
                    .foregroundStyle(AppTheme.paper.fg)
                Text(n.rawValue)
                    .font(.dsLabel(8))
                    .foregroundStyle(AppTheme.paper.fg3)
            }
            .frame(height: 44)
        }
    }
    .padding(24)
    .background(AppTheme.paper.bg)
    .appTheme(.paper)
    .frame(width: 560)
}
#endif
