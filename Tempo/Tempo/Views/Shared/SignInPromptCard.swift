//
// SignInPromptCard.swift
// Tempo
//
// One Sign in with Apple surface for every signed-out entry point: Settings
// → Account and the Dashboard nudge. Apple's own button (the white one,
// since the app is dark — App Review wants the official look) as a
// full-width pill inside a Tide glass card, with a one-line reason to sign in. Same SIWA
// flow as onboarding: nonce set in onRequest, token exchanged through
// AuthService.
//

import AuthenticationServices
import SwiftUI

struct SignInPromptCard: View {
    /// Which screen the card is drawn for: `tempo` for the screens not
    /// rebuilt yet (Settings), `tide` for rebuilt ones (Today). Both are drawn
    /// in Tide; the only difference is the identifier Today's tests look for.
    enum Style {
        case tempo
        case tide
    }

    var style: Style = .tempo
    /// Today passes a dismiss action ("Not now"); Settings doesn't.
    var onDismiss: (() -> Void)?

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @State
    private var isSigningIn = false
    @State
    private var errorMessage: String?
    @State
    private var pendingNonce: String?

    private static let title = String(localized: "Sign in to unlock your AI coach")
    private static let detail =
        String(localized: "Trainer imports, meal ideas and coaching need an account. Everything on this phone stays put.")

    var body: some View {
        switch style {
        case .tempo: card
        case .tide: card.accessibilityIdentifier("today.signin")
        }
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            if typeSize.isAccessibilitySize {
                // The words get the full card width; the icon and the close
                // button share the row above them.
                VStack(alignment: .leading, spacing: Tide.s3) {
                    HStack(alignment: .top, spacing: Tide.s3) {
                        TideIconTile(systemName: "sparkles", tint: mood.accent)
                        Spacer(minLength: 0)
                        dismissButton
                    }
                    copy
                }
            } else {
                HStack(alignment: .top, spacing: Tide.s3) {
                    TideIconTile(systemName: "sparkles", tint: mood.accent)
                    copy
                    Spacer(minLength: 0)
                    dismissButton
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
    }

    private var copy: some View {
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
    }

    @ViewBuilder
    private var dismissButton: some View {
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
                    .tint(Tide.text)
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
                errorMessage = String(localized: "Sign in failed. Try again.")
                return
            }
            do {
                try await services.authService.completeAppleSignIn(authorization: authorization, nonce: nonce)
                HapticManager.notification(.success)
            } catch {
                errorMessage = String(localized: "Sign in failed. Try again.")
            }
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = String(localized: "Sign in failed. Try again.")
            }
        }
    }
}
