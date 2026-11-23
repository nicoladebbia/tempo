//
// OnboardingSplashView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Onboarding Splash View

// Per STATE_MACHINES.md Section 10 — Animated splash, 1.8s, auto-advances.
// The mark rises out of the field, the wordmark follows.

struct OnboardingSplashView: View {
    let viewModel: OnboardingViewModel
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @State
    private var markShown = false
    @State
    private var wordShown = false

    var body: some View {
        VStack(spacing: Tide.s5) {
            Spacer()

            TempoLogoView(size: 96, showGlow: true)
                .scaleEffect(markShown ? 1 : 0.8)
                .opacity(markShown ? 1 : 0)

            Text("TEMPO")
                .font(Tide.numeral(34, .heavy))
                .tracking(6)
                .foregroundStyle(Tide.text)
                .opacity(wordShown ? 1 : 0)
                .offset(y: wordShown ? 0 : Tide.s2)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else {
                markShown = true
                wordShown = true
                return
            }
            withAnimation(Tide.lively) { markShown = true }
            withAnimation(Tide.lively.delay(0.25)) { wordShown = true }
        }
    }
}

#Preview {
    OnboardingSplashView(viewModel: OnboardingViewModel())
        .tidePage(energy: 1)
}
