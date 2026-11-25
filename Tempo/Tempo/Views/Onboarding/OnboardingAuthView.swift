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
// The Terms of Service and Privacy Policy are accepted here: the checkbox turns the Apple button
// on, and the acceptance is posted right after sign-in (the server answers 451 until it has it).
// When the person is already signed in (they came back to this step, or an older run stopped
// before the terms), the page shows only the checkbox and a Continue button.

struct OnboardingAuthView: View {
    @Bindable
    var viewModel: OnboardingViewModel
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @State
    private var isSigningIn = false
    @State
    private var isSubmitting = false
    @State
    private var signedIn = false
    @State
    private var errorMessage: String?
    /// Raw (un-hashed) nonce generated in the SIWA button's onRequest
    /// closure. Sent to the backend in onCompletion to verify the token.
    @State
    private var pendingNonce: String?

    // Placeholder URLs — replace with the final hosted documents before
    // launch per LAUNCH_PUNCH_LIST.md §1.5. The legal text itself lives
    // in /legal in this repo and should be uploaded to whatever host
    // (GitHub Pages / Notion / tempo.app) we settle on.
    private let termsURL = URL(string: "https://tempo.app/legal/terms")!
    private let privacyURL = URL(string: "https://tempo.app/legal/privacy")!

    var body: some View {
        OnboardingScaffold(
            title: "CREATE YOUR\nACCOUNT.",
            subtitle: signedIn
                ? "You are signed in with Apple. One more thing before we start."
                : "Sign in with Apple. Tempo never sees your Apple password."
        ) {
            // The two documents, side by side (stacked at large text sizes).
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Tide.s3))
                : AnyLayout(HStackLayout(spacing: Tide.s3))
            layout {
                legalLink(destination: termsURL, icon: "scroll", title: "Terms of Service")
                legalLink(destination: privacyURL, icon: "lock.shield", title: "Privacy Policy")
            }

            agreeToggle

            if signedIn {
                OnboardingNote("Signed in with Apple.", systemImage: "checkmark.seal.fill")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .onAppear {
            signedIn = services.authService.accessToken != nil
        }
    }

    // MARK: - Agree

    private var agreeToggle: some View {
        Toggle(isOn: $viewModel.tosAccepted) {
            Text("I have read and agree to the Terms of Service and the Privacy Policy.")
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.onboardingCheck)
        .padding(Tide.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(
            .regular.tint(viewModel.tosAccepted ? mood.accent.opacity(0.22) : Tide.glassCard),
            in: .rect(cornerRadius: Tide.tileRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: Tide.tileRadius, style: .continuous)
                .strokeBorder(viewModel.tosAccepted ? mood.accent : Color.clear, lineWidth: Tide.focusLine)
        }
        .animation(Tide.snap, value: viewModel.tosAccepted)
        .accessibilityIdentifier("onboardingAgreeToTerms")
    }

    /// A document to open: a symbol tile over its name, an arrow in the corner.
    private func legalLink(destination: URL, icon: String, title: String) -> some View {
        Link(destination: destination) {
            VStack(alignment: .leading, spacing: Tide.s4) {
                HStack(alignment: .top) {
                    TideIconTile(systemName: icon, tint: mood.accent, size: Tide.tile + Tide.s2)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    Spacer(minLength: Tide.s2)
                    Image(systemName: "arrow.up.right")
                        .font(Tide.label)
                        .foregroundStyle(Tide.text3)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
            .contentShape(.rect(cornerRadius: Tide.tileRadius))
        }
        .buttonStyle(TideCardPressStyle())
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Tide.s3) {
            if let message = errorMessage ?? viewModel.tosAcceptError {
                Text(message)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if signedIn {
                // Signed in already: only the terms are left.
                Button(viewModel.tosAcceptError == nil ? "CONTINUE" : "TRY AGAIN") {
                    Task { await submitTerms() }
                }
                .buttonStyle(.tidePrimary)
                .disabled(!viewModel.tosAccepted || isSubmitting)
                .accessibilityIdentifier("onboardingAuthContinue")
            } else if isSigningIn {
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
                // The button cannot be dimmed by `disabled` alone on every release, so it is
                // dimmed and blocked together until the terms are ticked.
                .disabled(!viewModel.tosAccepted)
                .opacity(viewModel.tosAccepted ? 1 : 0.4)
                .animation(Tide.snap, value: viewModel.tosAccepted)
                .accessibilityLabel("Sign in with Apple")
                .accessibilityHint(viewModel.tosAccepted ? "" : "Agree to the terms first")

                if !viewModel.tosAccepted {
                    Text("Agree to the terms to sign in.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // DEBUG: Bypass button for simulator testing
            #if DEBUG
                if !signedIn {
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
                    .accessibilityIdentifier("onboardingSkipSignIn")
                }
            #endif
        }
        .modifier(OnboardingFooterBar())
    }

    // MARK: - Actions

    private func submitTerms() async {
        isSubmitting = true
        defer { isSubmitting = false }
        await viewModel.submitToSAcceptance(apiClient: services.apiClient, isSignedIn: true)
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
            } catch {
                errorMessage = "Sign in failed. Please try again."
                return
            }
            signedIn = true
            prefillName(from: authorization)
            // A fresh sign-in may be a different Apple ID than the one the terms were recorded for
            // (the flag is saved on this phone, not on the account): record them for this one.
            viewModel.tosRecorded = false
            // The terms go to the server now: it answers 451 to everything else until then.
            await submitTerms()
        case let .failure(error):
            if (error as? ASAuthorizationError)?.code == .canceled {
                errorMessage = nil
            } else {
                errorMessage = "Sign in failed. Please try again."
            }
        }
    }

    /// Apple hands over the name on the first sign-in only: use it to start the next page.
    private func prefillName(from authorization: ASAuthorization) {
        guard viewModel.displayName.isEmpty,
              let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let components = credential.fullName
        else {
            return
        }
        let name = components.formatted(.name(style: .medium)).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            return
        }
        // The handle follows the name (see `OnboardingViewModel.displayName`).
        viewModel.displayName = name
    }
}

#Preview {
    OnboardingAuthView(viewModel: OnboardingViewModel())
        .tidePage(energy: 1)
        .environment(ServiceContainer.mock())
}
