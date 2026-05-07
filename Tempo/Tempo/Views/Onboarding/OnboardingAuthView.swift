//
// OnboardingAuthView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import AuthenticationServices
import SwiftUI

// MARK: - Onboarding Auth View

// Per STATE_MACHINES.md Section 10 — Sign in with Apple. REQUIRED. No skip.
// Per WIREFRAMES.md Screen 44 — Welcome + value prop + CTA

struct OnboardingAuthView: View {
    let viewModel: OnboardingViewModel
    @Environment(ServiceContainer.self)
    private var services
    @State
    private var isSigningIn = false
    @State
    private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Value prop
            // Per WIREFRAMES.md Screen 44 — "STOP MANAGING YOUR LIFE IN 5 DIFFERENT APPS."
            VStack(spacing: TempoSpacing.xl) {
                Text("STOP MANAGING YOUR LIFE\nIN 5 DIFFERENT APPS.")
                    .font(.system(size: 26, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Text("Training. Nutrition.\nRecovery. Academics.\nOne system. One score.\nZero excuses.")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, TempoSpacing.xl)

            Spacer()

            // Error message
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TempoSpacing.xl)
                    .padding(.bottom, TempoSpacing.lg)
            }

            // Sign in with Apple
            if isSigningIn {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.2)
            } else {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { _ in
                    Task { await signIn() }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 50)
                .frame(maxWidth: 320)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, TempoSpacing.xl)
            }

            // DEBUG: Bypass button for simulator testing
            #if DEBUG
                Button(action: {
                    // Skip authentication for testing
                    viewModel.advance()
                }) {
                    Text("Skip Sign In (Debug Only)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.top, TempoSpacing.md)
                }
            #endif

            Spacer().frame(height: TempoSpacing.xxxxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func signIn() async {
        isSigningIn = true
        errorMessage = nil

        do {
            try await services.authService.signInWithApple()
            // Success! Advance to next screen
            viewModel.advance()
        } catch AuthService.AuthError.signInCancelled {
            // User cancelled — no error to show
            errorMessage = nil
        } catch {
            errorMessage = "Sign in failed. Please try again."
        }

        isSigningIn = false
    }
}

#Preview {
    OnboardingAuthView(viewModel: OnboardingViewModel())
        .background(Color.black)
        .preferredColorScheme(.dark)
        .environment(ServiceContainer.mock())
}
