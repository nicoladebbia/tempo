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

    @State private var isSubmitting = false

    // Placeholder URLs — replace with the final hosted documents before
    // launch per LAUNCH_PUNCH_LIST.md §1.5. The legal text itself lives
    // in /legal in this repo and should be uploaded to whatever host
    // (GitHub Pages / Notion / tempo.app) we settle on.
    private let termsURL = URL(string: "https://tempo.app/legal/terms")!
    private let privacyURL = URL(string: "https://tempo.app/legal/privacy")!

    var body: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Text("ONE LAST\nTHING.")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Image(systemName: "doc.text.fill")
                .font(.system(size: 60))
                .foregroundStyle(Color.tempoAmber)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: TempoSpacing.md) {
                Link(destination: termsURL) {
                    HStack {
                        Image(systemName: "scroll")
                            .foregroundStyle(Color.tempoAmber)
                            .frame(width: 24)
                        Text("Terms of Service")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
                Link(destination: privacyURL) {
                    HStack {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(Color.tempoAmber)
                            .frame(width: 24)
                        Text("Privacy Policy")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.xxl)

            Toggle(isOn: $viewModel.tosAccepted) {
                Text("I have read and agree to the Terms of Service and the Privacy Policy.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .toggleStyle(SwitchToggleStyle(tint: Color.tempoAmber))
            .padding(.horizontal, TempoSpacing.xxl)

            if let err = viewModel.tosAcceptError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.tempoError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TempoSpacing.lg)
            }

            Spacer()

            OnboardingPrimaryButton(
                title: "CONTINUE",
                enabled: viewModel.tosAccepted && !isSubmitting
            ) {
                Task {
                    isSubmitting = true
                    await viewModel.submitToSAcceptance(apiClient: services.apiClient)
                    isSubmitting = false
                }
            }

            Spacer().frame(height: TempoSpacing.xxxl)
        }
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    TermsAcceptanceView(viewModel: vm)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .environment(ServiceContainer.mock())
}
