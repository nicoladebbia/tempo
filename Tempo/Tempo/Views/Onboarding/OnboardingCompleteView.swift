//
// OnboardingCompleteView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Onboarding Complete View

// Per STATE_MACHINES.md Section 10 — "Welcome to Tempo" with first day briefing. Terminal.
// Per BUILD_PLAN step 16.1 — Sets isOnboardingComplete = true, shows main tab view.

struct OnboardingCompleteView: View {
    let viewModel: OnboardingViewModel
    @State
    private var opacity: Double = 0
    @State
    private var scale: Double = 0.9

    var body: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(Color.tempoSuccess)
                .scaleEffect(scale)
                .opacity(opacity)

            Text("YOU'RE IN.")
                .font(.system(size: 32, weight: .black))
                .foregroundStyle(.white)
                .opacity(opacity)

            Text("Welcome to Tempo.\nYour operating system starts now.")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .opacity(opacity)

            Spacer()

            OnboardingPrimaryButton(title: "LET'S GO", enabled: true) {
                viewModel.complete()
            }

            Spacer().frame(height: TempoSpacing.xxxl)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                opacity = 1
                scale = 1
            }
        }
    }
}

#Preview {
    OnboardingCompleteView(viewModel: OnboardingViewModel())
        .background(Color.black)
        .preferredColorScheme(.dark)
}
