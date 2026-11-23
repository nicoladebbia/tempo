//
// TermsAcceptanceView.swift
// Tempo
//
// Required ToS + Privacy Policy acceptance step. Per
// LAUNCH_PUNCH_LIST.md §3.5 and Apple App Store Review Guideline 5.1.1.
//
// The user must check the agreement box before the Continue button
// enables. Both legal URLs open in Safari (no in-app browser dependency).
// On submit we POST /v1/user/accept-tos which records the timestamp
// server-side; the ToSGateMiddleware then lets all other requests
// through.
//

import SwiftUI

struct TermsAcceptanceView: View {
    @Bindable
    var viewModel: OnboardingViewModel
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood

    @State private var isSubmitting = false

    // Placeholder URLs — replace with the final hosted documents before
    // launch per LAUNCH_PUNCH_LIST.md §1.5. The legal text itself lives
    // in /legal in this repo and should be uploaded to whatever host
    // (GitHub Pages / Notion / tempo.app) we settle on.
    private let termsURL = URL(string: "https://tempo.app/legal/terms")!
    private let privacyURL = URL(string: "https://tempo.app/legal/privacy")!

    var body: some View {
        OnboardingScaffold(
            title: "ONE LAST\nTHING.",
            primaryTitle: "CONTINUE",
            primaryEnabled: viewModel.tosAccepted && !isSubmitting,
            primaryAction: {
                Task {
                    isSubmitting = true
                    await viewModel.submitToSAcceptance(
                        apiClient: services.apiClient,
                        isSignedIn: services.authService.accessToken != nil
                    )
                    isSubmitting = false
                }
            },
            centered: true
        ) {
            OnboardingHeroTile(systemName: "doc.text.fill")

            VStack(spacing: 0) {
                legalLink(destination: termsURL, icon: "scroll", title: "Terms of Service")
                Divider().overlay(Tide.hairline)
                legalLink(destination: privacyURL, icon: "lock.shield", title: "Privacy Policy")
            }
            .onboardingCard()

            Toggle(isOn: $viewModel.tosAccepted) {
                Text("I have read and agree to the Terms of Service and the Privacy Policy.")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.tempo)

            if let err = viewModel.tosAcceptError {
                Text(err)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func legalLink(destination: URL, icon: String, title: String) -> some View {
        Link(destination: destination) {
            HStack(spacing: Tide.s3) {
                Image(systemName: icon)
                    .font(Tide.headline)
                    .foregroundStyle(mood.accent)
                    .frame(width: Tide.icon)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Tide.hit)
            .contentShape(.rect)
        }
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    TermsAcceptanceView(viewModel: vm)
        .tidePage(energy: 1)
        .environment(ServiceContainer.mock())
}
