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

struct OnboardingSplashView: View {
    let viewModel: OnboardingViewModel
    @State
    private var opacity: Double = 0
    @State
    private var scale: Double = 0.8

    var body: some View {
        VStack(spacing: TempoSpacing.lg) {
            Spacer()

            TempoLogoView(size: 80, showGlow: true)
                .scaleEffect(scale)
                .opacity(opacity)

            Text("TEMPO")
                .font(.system(size: 28, weight: .black))
                .tracking(3)
                .foregroundStyle(.white)
                .opacity(opacity)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                opacity = 1
                scale = 1
            }
        }
    }
}

#Preview {
    OnboardingSplashView(viewModel: OnboardingViewModel())
        .background(Color.black)
        .preferredColorScheme(.dark)
}
