//
// OnboardingCompleteView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI

// MARK: - Onboarding Complete View

// Per STATE_MACHINES.md Section 10 — "Welcome to Tempo" with first day briefing. Terminal.
// Per BUILD_PLAN step 16.1 — Sets isOnboardingComplete = true, shows main tab view.
//
// On appear, materialises the captured daily-plan profile into SwiftData and
// fires a non-blocking sync to the backend. Per INTELLIGENCE_REMEDIATION_PLAN.md §8.

struct OnboardingCompleteView: View {
    let viewModel: OnboardingViewModel

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext

    @State private var opacity: Double = 0
    @State private var scale: Double = 0.9
    @State private var didPersist = false

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
            persistDailyPlanProfileIfNeeded()
        }
    }

    /// Materialise the captured daily-plan profile into SwiftData and push to
    /// the backend. Idempotent — guarded by `didPersist` so re-entering this
    /// view (e.g. via state restoration) doesn't insert duplicate rows.
    private func persistDailyPlanProfileIfNeeded() {
        guard !didPersist else { return }
        didPersist = true

        // Local SwiftData first — survives offline, and is what the meal
        // planner reads for the eating window. Upsert, so a relaunch on this
        // step never leaves a duplicate row.
        do {
            try viewModel.persistDailyPlanProfile(in: modelContext)
        } catch {
            print("[onboarding] persistDailyPlanProfile local save failed: \(error.localizedDescription)")
        }

        // Backend sync — non-blocking. Failures are logged in the VM helper.
        Task {
            await viewModel.syncDailyPlanProfile(apiClient: services.apiClient)
        }
    }
}

#Preview {
    OnboardingCompleteView(viewModel: OnboardingViewModel())
        .background(Color.black)
        .preferredColorScheme(.dark)
}
