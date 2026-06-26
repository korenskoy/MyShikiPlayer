//
//  OAuthRedirectConsentView.swift
//  MyShikiPlayer
//

import SwiftUI

/// Consent sheet shown when the OAuth token endpoint redirects to a host that
/// isn't a known Shikimori mirror. The user must tick "I understand" AND wait
/// out a short cool-off before the "Trust" button enables — deliberate friction
/// so the credentialed request isn't forwarded on a reflexive click.
struct OAuthRedirectConsentView: View {
    @Environment(\.appTheme) private var theme
    let pending: OAuthRedirectConsentCoordinator.PendingConsent
    let onApprove: () -> Void
    let onDeny: () -> Void

    private static let coolOffSeconds = 5
    @State private var understood = false
    @State private var secondsLeft = OAuthRedirectConsentView.coolOffSeconds

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.orange)
                Text("Вход перенаправляется на другой хост")
                    .font(.title3.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Сервер авторизации просит отправить запрос входа на хост, "
                    + "которого нет в списке известных зеркал Shikimori:")
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(pending.fromHost.isEmpty ? "?" : pending.fromHost)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text(pending.host).fontWeight(.semibold).foregroundStyle(.tint)
                }
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            Text("Этот запрос содержит секреты приложения и токен обновления. "
                + "Доверяйте хосту, только если уверены, что это официальный домен "
                + "Shikimori. Иначе нажмите «Отмена» — секреты не будут отправлены.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle(isOn: $understood) {
                Text("Я подтверждаю, что понимаю, что делаю, и доверяю этому хосту")
            }

            HStack {
                Button("Отмена", role: .cancel, action: onDeny)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: onApprove) {
                    Text(secondsLeft > 0 ? "Доверять (\(secondsLeft))" : "Доверять")
                        .frame(minWidth: 150)
                }
                .buttonStyle(.accent)
                .disabled(!understood || secondsLeft > 0)
            }
        }
        .padding(24)
        .frame(width: 470)
        .background(theme.bg)
        .task {
            // Cool-off so the warning is read, not clicked through.
            secondsLeft = Self.coolOffSeconds
            while secondsLeft > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                secondsLeft -= 1
            }
        }
    }
}
