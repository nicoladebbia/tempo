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
    @State
    private var barFilled = false
    @ScaledMetric(relativeTo: .largeTitle)
    private var wordSize: CGFloat = Tide.numeralM

    var body: some View {
        VStack(spacing: Tide.s5) {
            Spacer()

            TempoLogoView(size: Tide.dialSheet - Tide.s6, showGlow: true)
                .scaleEffect(markShown ? 1 : 0.8)
                .opacity(markShown ? 1 : 0)

            Text("TEMPO")
                .font(Tide.numeral(wordSize, .heavy))
                .tracking(Tide.s1 + Tide.hair)
                .foregroundStyle(Tide.text)
                .opacity(wordShown ? 1 : 0)
                .offset(y: wordShown ? 0 : Tide.s2)

            // The hook's beat: a short bar that fills as the app wakes up.
            TideLevelBar(progress: barFilled ? 1 : 0, height: Tide.barSlim)
                .background(Tide.fill, in: .capsule)
                .frame(width: Tide.dialSheet - Tide.s6)
                .opacity(wordShown ? 1 : 0)
                .accessibilityHidden(true)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else {
                markShown = true
                wordShown = true
                barFilled = true
                return
            }
            withAnimation(Tide.lively) { markShown = true }
            withAnimation(Tide.lively.delay(0.25)) { wordShown = true }
            withAnimation(.easeInOut(duration: 1.4).delay(0.3)) { barFilled = true }
        }
    }
}

#Preview {
    OnboardingSplashView(viewModel: OnboardingViewModel())
        .tidePage(energy: 1)
}
