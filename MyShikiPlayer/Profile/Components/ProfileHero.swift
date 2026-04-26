//
//  ProfileHero.swift
//  MyShikiPlayer
//
//  Top profile block: avatar + nickname + name + location/website + last online.
//

import SwiftUI

struct ProfileHero: View {
    @Environment(\.appTheme) private var theme
    let profile: UserProfile

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            avatar
            VStack(alignment: .leading, spacing: 6) {
                Text(profile.nickname)
                    .font(.dsTitle(28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(theme.fg)

                if let name = profile.name, !name.isEmpty, name != profile.nickname {
                    Text(name)
                        .font(.dsBody(14))
                        .foregroundStyle(theme.fg2)
                }

                metaLine
            }
            Spacer()
        }
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatar: some View {
        if let url = avatarURL {
            CachedRemoteImage(
                url: url,
                contentMode: .fill,
                placeholder: { fallback },
                failure: { fallback }
            )
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.line, lineWidth: 1)
            )
        } else {
            fallback
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var avatarURL: URL? {
        let raw = profile.image?.x160
            ?? profile.image?.x148
            ?? profile.image?.x80
            ?? profile.image?.x64
            ?? profile.avatar
        guard let raw else { return nil }
        if raw.hasPrefix("http") { return URL(string: raw) }
        if raw.hasPrefix("/") { return ShikimoriURL.media(path: raw) }
        return URL(string: raw)
    }

    private var fallback: some View {
        ZStack {
            Rectangle().fill(theme.accent)
            Text(profile.nickname.first.map { String($0).uppercased() } ?? "?")
                .font(.dsTitle(36, weight: .heavy))
                .foregroundStyle(Color.white)
        }
    }

    // MARK: - Meta line

    private var metaLine: some View {
        HStack(spacing: 12) {
            if let online = profile.lastOnlineAt {
                Label(Self.lastOnlineText(online), systemImage: "clock")
                    .labelStyle(.titleOnly)
                    .font(.dsMono(11))
                    .foregroundStyle(theme.fg3)
            }
            if let locale = profile.locale, !locale.isEmpty {
                Text(locale.uppercased())
                    .font(.dsMono(11, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(theme.fg3)
            }
            if let website = profile.website, !website.isEmpty {
                Text(website)
                    .font(.dsMono(11))
                    .foregroundStyle(theme.fg3)
                    .lineLimit(1)
            }
        }
    }

    private static func lastOnlineText(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.locale = Locale(identifier: "ru_RU")
        fmt.unitsStyle = .short
        return "был(а) \(fmt.localizedString(for: date, relativeTo: Date()))"
    }
}
