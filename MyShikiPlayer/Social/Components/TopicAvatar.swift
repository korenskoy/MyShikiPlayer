//
//  TopicAvatar.swift
//  MyShikiPlayer
//
//  Square user avatar — sized by callers (32pt in TopicCard / LinearPostRow,
//  40pt in TopicDetailView hero).
//  Expands UserImageSet / legacy `avatar` into a URL.
//

import SwiftUI

struct TopicAvatar: View {
    @Environment(\.appTheme) private var theme
    let user: TopicUser?
    let size: CGFloat

    var body: some View {
        ZStack {
            if let url = avatarURL {
                CachedRemoteImage(
                    url: url,
                    contentMode: .fill,
                    placeholder: { fallback },
                    failure: { fallback }
                )
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(theme.line, lineWidth: 1)
        )
    }

    private var avatarURL: URL? {
        let raw = user?.image?.x80
            ?? user?.image?.x64
            ?? user?.image?.x48
            ?? user?.avatar
        guard let raw else { return nil }
        if raw.hasPrefix("http") { return URL(string: raw) }
        if raw.hasPrefix("/") { return ShikimoriURL.media(path: raw) }
        return URL(string: raw)
    }

    private var fallback: some View {
        let initial = user?.nickname?.first.map { String($0).uppercased() } ?? "?"
        return ZStack {
            theme.accent
            Text(initial)
                .font(.dsTitle(size * 0.45, weight: .heavy))
                .foregroundStyle(Color.white)
        }
    }
}
