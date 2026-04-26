//
//  NavigationState.swift
//  MyShikiPlayer
//

import Foundation
import Combine

@MainActor
final class NavigationState: ObservableObject {
    enum Branch: String, CaseIterable, Identifiable, Codable {
        case home
        case catalog
        case schedule
        case social
        case myLists
        case history
        /// Profile is not shown in the nav bar — it opens via a tap on the avatar.
        case profile

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home:     return "Главная"
            case .catalog:  return "Каталог"
            case .schedule: return "Календарь"
            case .social:   return "Лента"
            case .myLists:  return "Мои списки"
            case .history:  return "История"
            case .profile:  return "Профиль"
            }
        }

        /// Icon name from DesignSystem (DSIconName).
        var iconName: String {
            switch self {
            case .home:     return "home"
            case .catalog:  return "grid"
            case .schedule: return "calendar"
            case .social:   return "users"
            case .myLists:  return "bookmark"
            case .history:  return "clock"
            case .profile:  return "user"
            }
        }

        /// Branches shown in the horizontal nav bar. Profile is reached separately via the avatar.
        static let navBarCases: [Branch] = [.home, .catalog, .myLists, .schedule, .social, .history]
    }

    @Published var selectedBranch: Branch = .myLists
}
