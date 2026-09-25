//
// SettingsSignInCard.swift
// Tempo
//
// Sign in with Apple from Settings → Account. Onboarding is the only other
// place to sign in, so a user who finished onboarding without a backend
// session (Debug "Skip Sign In", or a lost Keychain) had no way back — every
// AI call failed with "Your session has expired". Same SIWA flow as
// OnboardingAuthView: native button, nonce set in onRequest, token exchanged
// through AuthService.
//

import AuthenticationServices
import SwiftUI

struct SettingsSignInCard: View {
    @Environment(ServiceContainer.self)
    private var services
    @State
    private var isSigningIn = false
    @State
    private var errorMessage: String?
    @State
    private var pendingNonce: String?

    var body: some View {
        SettingsFormCard(
            title: "Not signed in",
            footnote: "Sign in to turn on the AI coach, meal suggestions and sync. Your data on this phone stays as it is."
        ) {
            VStack(spacing: TempoSpacing.sm) {
                if isSigningIn {
                    ProgressView()
                        .frame(height: 50)
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        let nonce = services.authService.makeNonce()
                        pendingNonce = nonce.raw
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = nonce.hashed
                    } onCompletion: { result in
                        Task { await handleAppleResult(result) }
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("Sign in with Apple")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                }
            }
            .padding(.vertical, TempoSpacing.sm)
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        switch result {
        case let .success(authorization):
            guard let nonce = pendingNonce else {
                errorMessage = "Sign in failed. Please try again."
                return
            }
            do {
                try await services.authService.completeAppleSignIn(
                    authorization: authorization,
                    nonce: nonce
                )
                HapticManager.notification(.success)
            } catch {
                errorMessage = "Sign in failed. Please try again."
            }
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Sign in failed. Please try again."
            }
        }
    }
}
