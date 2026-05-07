//
// NutriTrackConnectStepView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - NutriTrack Connect Step View (Onboarding)

// Per STATE_MACHINES.md Section 10 — Connect NutriTrack. OPTIONAL.

struct NutriTrackConnectStepView: View {
    @Bindable
    var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Text("FUEL YOUR\nPERFORMANCE.")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Image(systemName: "fork.knife")
                .font(.system(size: 60))
                .foregroundStyle(Color.tempoAmber)

            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                benefitRow(icon: "chart.bar.fill", text: "Macro tracking")
                benefitRow(icon: "target", text: "Protein targets")
                benefitRow(icon: "clock.fill", text: "Meal timing")
            }
            .padding(.horizontal, TempoSpacing.xxl)

            Spacer()

            OnboardingPrimaryButton(title: "CONNECT NUTRITRACK", enabled: true) {
                viewModel.nutritrackConnected = true
                viewModel.advance()
            }

            OnboardingSkipButton { viewModel.skip() }

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

    NutriTrackConnectStepView(viewModel: vm)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
