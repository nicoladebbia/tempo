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
    /// Raw (un-hashed) nonce generated in the SIWA button's onRequest
    /// closure. Sent to the backend in onCompletion to verify the token.
    @State
    private var pendingNonce: String?
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    private static let modules: [(title: String, icon: String, tint: Color)] = [
        ("Training", "dumbbell.fill", Tide.fat),
        ("Nutrition", "fork.knife", Tide.carbs),
        ("Recovery", "heart.fill", Tide.protein),
        ("Academics", "graduationcap.fill", Tide.water),
    ]

    private var moduleColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Tide.s3), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4)
    }

    var body: some View {
        // Per WIREFRAMES.md Screen 44 — "STOP MANAGING YOUR LIFE IN 5 DIFFERENT APPS."
        OnboardingScaffold(
            title: "STOP MANAGING YOUR LIFE\nIN 5 DIFFERENT APPS.",
            centered: true
        ) {
            // The five apps fold into one: the four areas, then one line.
            VStack(spacing: Tide.s5) {
                LazyVGrid(columns: moduleColumns, spacing: Tide.s3) {
                    ForEach(Self.modules, id: \.title) { module in
                        VStack(spacing: Tide.s2) {
                            TideIconTile(systemName: module.icon, tint: module.tint, size: Tide.tile + Tide.s2)
                            Text(module.title)
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                                .lineLimit(1)
                                .minimumScaleFactor(Tide.labelShrink)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .tideCard(padding: Tide.s4, radius: Tide.tileRadius)

                // ...become one.
                Image(systemName: "chevron.down")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
                TempoLogoView(size: Tide.dialSheet - Tide.s6 * 2, showGlow: true)

                Text("One system. One score.\nZero excuses.")
                    .font(Tide.headline.weight(.regular))
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
                    .lineSpacing(Tide.s1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            signInFooter
        }
    }

    private var signInFooter: some View {
        VStack(spacing: Tide.s3) {
            if let errorMessage {
                Text(errorMessage)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Sign in with Apple
            if isSigningIn {
                ProgressView()
                    .tint(Tide.text)
                    .scaleEffect(1.2)
                    .frame(height: Tide.fieldHeight)
            } else {
                // Use SignInWithAppleButton's OWN flow. Wrapping it in an
                // outer Button (even with allowsHitTesting(false) on the
                // inner button) caused the UIKit-backed control to swallow
                // the tap on iOS 26 — the button was dead. The native
                // onRequest/onCompletion path handles its own touch and is
                // the App-Store-compliant pattern. We set the nonce in
                // onRequest and exchange the result via AuthService —
                // crucially WITHOUT firing a second ASAuthorizationController.
                SignInWithAppleButton(.signIn) { request in
                    let nonce = services.authService.makeNonce()
                    pendingNonce = nonce.raw
                    request.requestedScopes = [.fullName, .email]
                    request.nonce = nonce.hashed
                } onCompletion: { result in
                    Task { await handleAppleResult(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: Tide.fieldHeight)
                .frame(maxWidth: .infinity)
                .clipShape(.capsule)
                .accessibilityLabel("Sign in with Apple")
            }

            // DEBUG: Bypass button for simulator testing
            #if DEBUG
                Button(action: {
                    // Skip authentication for testing
                    viewModel.advance()
                }) {
                    Text("Skip Sign In (Debug Only)")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .frame(minHeight: Tide.hit)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            #endif
        }
        .modifier(OnboardingFooterBar())
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
                viewModel.advance()
            } catch {
                errorMessage = "Sign in failed. Please try again."
            }
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code == .canceled {
                errorMessage = nil
            } else {
                errorMessage = "Sign in failed. Please try again."
            }
        }
    }
}

#Preview {
    OnboardingAuthView(viewModel: OnboardingViewModel())
        .tidePage(energy: 1)
        .environment(ServiceContainer.mock())
}
