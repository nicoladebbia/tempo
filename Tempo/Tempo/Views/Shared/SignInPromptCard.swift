//
// SignInPromptCard.swift
// Tempo
//
// One Sign in with Apple surface for every signed-out entry point: Settings
// → Account and the Dashboard nudge. Apple's own button (black in light
// mode, white in dark — App Review wants the official look) as a full-width
// pill inside a Tempo card, with a one-line reason to sign in. Same SIWA
// flow as onboarding: nonce set in onRequest, token exchanged through
// AuthService.
//

import AuthenticationServices
import SwiftUI

struct SignInPromptCard: View {
    /// Which design language the card is drawn in: `tempo` for the screens
    /// not rebuilt yet (Settings), `tide` for rebuilt ones (Today).
    enum Style {
        case tempo
        case tide
    }

    var style: Style = .tempo
    /// Today passes a dismiss action ("Not now"); Settings doesn't.
    var onDismiss: (() -> Void)?

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.colorScheme)
    private var colorScheme
    @Environment(\.tideMood)
    private var mood
    @State
    private var isSigningIn = false
    @State
    private var errorMessage: String?
    @State
    private var pendingNonce: String?

    private static let title = "Sign in to unlock your AI coach"
    private static let detail =
        "Trainer imports, meal ideas and coaching need an account. Everything on this phone stays put."

    var body: some View {
        switch style {
        case .tempo: tempoCard
        case .tide: tideCard
        }
    }

    // MARK: Tide

    private var tideCard: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            HStack(alignment: .top, spacing: Tide.s3) {
                Image(systemName: "sparkles")
                    .font(Tide.headline)
                    .foregroundStyle(mood.accent)
                    .frame(width: Tide.icon, height: Tide.icon)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tide.s1) {
                    Text(Self.title)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.detail)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(Tide.label)
                            .foregroundStyle(Tide.text2)
                            .frame(width: Tide.hit, height: Tide.hit)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Not now")
                }
            }
            // Always the white button: Tide is a dark surface.
            appleButton(.white)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
            }
        }
        .tideCard()
        .accessibilityIdentifier("today.signin")
    }

    // MARK: Tempo (screens not rebuilt yet)

    private var tempoCard: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            HStack(alignment: .top, spacing: TempoSpacing.sm) {
                Image(systemName: "sparkles")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoSignal)
                    .frame(width: 36, height: 36)
                    .background(Color.tempoSignal.opacity(TempoOpacity.o15))
                    .clipShape(Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    Text(Self.title)
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(Self.detail)
                        .font(.tempoFootnote)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.tempoCaption1.weight(.semibold))
                            .foregroundStyle(Color.tempoTextTertiary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Not now")
                }
            }

            appleButton(colorScheme == .dark ? .white : .black)
                // Re-create on scheme change: the style is read once at init.
                .id(colorScheme)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoError)
            }
        }
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .strokeBorder(Color.tempoSignal.opacity(TempoOpacity.o15), lineWidth: 1)
        )
    }

    // MARK: Shared

    /// Apple's button at Apple's size (their guidelines set the height).
    private static let appleButtonHeight: CGFloat = 50

    private func appleButton(_ buttonStyle: SignInWithAppleButton.Style) -> some View {
        ZStack {
            SignInWithAppleButton(.signIn) { request in
                let nonce = services.authService.makeNonce()
                pendingNonce = nonce.raw
                request.requestedScopes = [.fullName, .email]
                request.nonce = nonce.hashed
            } onCompletion: { result in
                Task { await handleAppleResult(result) }
            }
            .signInWithAppleButtonStyle(buttonStyle)
            .frame(height: Self.appleButtonHeight)
            .clipShape(Capsule())
            .opacity(isSigningIn ? 0 : 1)
            .disabled(isSigningIn)
            .accessibilityLabel("Sign in with Apple")

            if isSigningIn {
                ProgressView()
            }
        }
        .frame(height: Self.appleButtonHeight)
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        switch result {
        case let .success(authorization):
            guard let nonce = pendingNonce else {
                errorMessage = "Sign in failed. Try again."
                return
            }
            do {
                try await services.authService.completeAppleSignIn(authorization: authorization, nonce: nonce)
                HapticManager.notification(.success)
            } catch {
                errorMessage = "Sign in failed. Try again."
            }
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Sign in failed. Try again."
            }
        }
    }
}
