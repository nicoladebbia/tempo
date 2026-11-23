//
// AIConsentView.swift
// Tempo
//
// AI data-sharing consent step. Required by AI_INTELLIGENCE_ENGINE.md §11.3
// and gated by SubscriptionMiddleware on the backend — without consent every
// AI route returns 402 ai_consent_required.
//
// Per INTELLIGENCE_REMEDIATION_PLAN.md §4.6.
//

import SwiftUI

struct AIConsentView: View {
    @Bindable
    var viewModel: OnboardingViewModel
    @Environment(ServiceContainer.self)
    private var services

    @State private var isSubmitting = false

    var body: some View {
        OnboardingScaffold(
            title: "ENABLE AI\nCOACHING.",
            primaryTitle: "ENABLE AI FEATURES",
            primaryEnabled: !isSubmitting,
            primaryAction: { submit(consent: true) },
            skipTitle: "Skip — use rule-based only",
            skipAction: isSubmitting ? nil : { submit(consent: false) },
            centered: true
        ) {
            OnboardingHeroTile(systemName: "brain.head.profile")

            VStack(alignment: .leading, spacing: Tide.s3) {
                OnboardingBenefitRow(systemImage: "chart.line.uptrend.xyaxis", text: "Weekly intelligence reports")
                OnboardingBenefitRow(systemImage: "sparkles", text: "Pattern detection across modules")
                OnboardingBenefitRow(systemImage: "fork.knife", text: "AI-generated meal plans & coach")
                OnboardingBenefitRow(systemImage: "bolt.heart.fill", text: "Recovery-adjusted prescriptions")
            }
            .onboardingCard()

            OnboardingNote(
                "Tempo sends your training, sleep, and nutrition data to Anthropic only when you trigger an AI feature. Your data is never used to train their models. Toggle this off anytime in Settings.",
                systemImage: "lock.fill"
            )

            if let err = viewModel.aiConsentError {
                Text(err)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func submit(consent: Bool) {
        Task {
            isSubmitting = true
            await viewModel.setAIConsent(
                consent,
                apiClient: services.apiClient,
                isSignedIn: services.authService.accessToken != nil
            )
            isSubmitting = false
        }
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    AIConsentView(viewModel: vm)
        .tidePage(energy: 1)
        .environment(ServiceContainer.mock())
}
