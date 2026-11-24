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
// The two documents are two cards to open; the consent is one big tick that
// lights its card when checked.
//

import SwiftUI

struct TermsAcceptanceView: View {
    @Bindable
    var viewModel: OnboardingViewModel
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.tideMood)
    private var mood
    @Environment(\.dynamicTypeSize)
    private var typeSize

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
            errorMessage: viewModel.tosAcceptError,
            centered: true
        ) {
            // The two documents, side by side (stacked at large text sizes).
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Tide.s3))
                : AnyLayout(HStackLayout(spacing: Tide.s3))
            layout {
                legalLink(destination: termsURL, icon: "scroll", title: "Terms of Service")
                legalLink(destination: privacyURL, icon: "lock.shield", title: "Privacy Policy")
            }

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
        }
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
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    TermsAcceptanceView(viewModel: vm)
        .tidePage(energy: 1)
        .environment(ServiceContainer.mock())
}
