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
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Text("ENABLE AI\nCOACHING.")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundStyle(Color.tempoAmber)

            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                benefitRow(icon: "chart.line.uptrend.xyaxis", text: "Weekly intelligence reports")
                benefitRow(icon: "sparkles", text: "Pattern detection across modules")
                benefitRow(icon: "fork.knife", text: "AI-generated meal plans & coach")
                benefitRow(icon: "bolt.heart.fill", text: "Recovery-adjusted prescriptions")
            }
            .padding(.horizontal, TempoSpacing.xxl)

            Text("Tempo sends your training, sleep, and nutrition data to Anthropic only when you trigger an AI feature. Your data is never used to train their models. Toggle this off anytime in Settings.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.lg)

            if let err = viewModel.aiConsentError {
                Text(err)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.tempoError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TempoSpacing.lg)
            }

            Spacer()

            OnboardingPrimaryButton(title: "ENABLE AI FEATURES", enabled: !isSubmitting) {
                Task {
                    isSubmitting = true
                    await viewModel.setAIConsent(true, apiClient: services.apiClient)
                    isSubmitting = false
                }
            }

            Button {
                Task {
                    isSubmitting = true
                    await viewModel.setAIConsent(false, apiClient: services.apiClient)
                    isSubmitting = false
                }
            } label: {
                Text("Skip — use rule-based only")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .disabled(isSubmitting)

            Spacer().frame(height: TempoSpacing.xxxl)
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.tempoAmber)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    AIConsentView(viewModel: vm)
        .background(Color.black)
        .preferredColorScheme(.dark)
        .environment(ServiceContainer.mock())
}
