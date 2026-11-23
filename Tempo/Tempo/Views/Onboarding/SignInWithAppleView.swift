//
// SignInWithAppleView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import AuthenticationServices
import SwiftUI

// MARK: - Sign In with Apple View

// Per BUILD_PLAN step 6.5 — Sign in with Apple button using AuthenticationServices.

struct SignInWithAppleView: View {
    @Environment(ServiceContainer.self)
    private var services
    @State
    private var isSigningIn = false
    @State
    private var errorMessage: String?

    var body: some View {
        VStack(spacing: Tide.s8) {
            Spacer()

            // App logo and title
            VStack(spacing: Tide.s4) {
                TempoLogoView(size: 96, showGlow: true)

                Text("TEMPO")
                    .font(Tide.numeral(34, .heavy))
                    .tracking(6)
                    .foregroundStyle(Tide.text)

                Text("Your Life Operating System")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
            }

            Spacer()

            // Error message
            if let errorMessage {
                Text(errorMessage)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Tide.edge)
            }

            // Sign in button
            if isSigningIn {
                ProgressView()
                    .tint(Tide.text)
                    .frame(height: Tide.fieldHeight)
                    .padding(.bottom, Tide.s5)
            } else {
                Button(action: {
                    Task { await signIn() }
                }) {
                    SignInWithAppleButton(.signIn, onRequest: { _ in }, onCompletion: { _ in })
                        .signInWithAppleButtonStyle(.white)
                        .allowsHitTesting(false)
                        .frame(height: Tide.fieldHeight)
                        .frame(maxWidth: .infinity)
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s5)
                .accessibilityLabel("Sign in with Apple")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tidePage(energy: 1)
    }

    private func signIn() async {
        isSigningIn = true
        errorMessage = nil

        do {
            try await services.authService.signInWithApple()
        } catch AuthService.AuthError.signInCancelled {
            // User cancelled — no error to show
        } catch {
            errorMessage = "Sign in failed. Please try again."
        }

        isSigningIn = false
    }
}
