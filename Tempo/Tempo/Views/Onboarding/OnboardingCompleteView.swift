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
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @Environment(\.tideMood)
    private var mood
    @ScaledMetric(relativeTo: .largeTitle)
    private var titleSize: CGFloat = Tide.numeralL

    @State private var shown = false
    @State private var pulse = false
    @State private var didPersist = false

    /// The closing ring: `dialSheet` plus a hand.
    private let ring = Tide.dialSheet + Tide.s2

    var body: some View {
        VStack(spacing: Tide.s6) {
            Spacer()

            // The ring closes, the check lands.
            ZStack {
                // One soft ripple leaves the ring once it has closed.
                Circle()
                    .strokeBorder(mood.accent.opacity(0.5), lineWidth: Tide.hair)
                    .frame(width: ring, height: ring)
                    .scaleEffect(pulse ? 1.7 : 1)
                    .opacity(shown && !pulse ? 0.8 : 0)
                TideRing(progress: shown ? 1 : 0, color: mood.accent, lineWidth: Tide.s2)
                    .frame(width: ring, height: ring)
                Image(systemName: "checkmark")
                    .font(Tide.numeral(Tide.numeralL + Tide.s3, .heavy))
                    .foregroundStyle(mood.accent)
                    .scaleEffect(shown ? 1 : 0.5)
                    .opacity(shown ? 1 : 0)
            }
            .accessibilityHidden(true)

            VStack(spacing: Tide.s2) {
                Text("YOU'RE IN.")
                    .font(Tide.numeral(titleSize, .heavy))
                    .foregroundStyle(Tide.text)
                    .accessibilityAddTraits(.isHeader)

                Text("Welcome to Tempo.\nYour operating system starts now.")
                    .font(Tide.headline.weight(.regular))
                    .foregroundStyle(Tide.text2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : Tide.s3)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, Tide.edge)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("LET'S GO") {
                viewModel.complete()
            }
            .buttonStyle(.tidePrimary)
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s2)
        }
        .sensoryFeedback(.success, trigger: shown)
        .onAppear {
            if reduceMotion {
                shown = true
            } else {
                withAnimation(Tide.lively.delay(0.15)) { shown = true }
                withAnimation(.easeOut(duration: 1.3).delay(1.1)) { pulse = true }
            }
            persistDailyPlanProfileIfNeeded()
        }
    }

    /// Materialise the captured daily-plan profile into SwiftData and push to
    /// the backend. Idempotent — guarded by `didPersist` so re-entering this
    /// view (e.g. via state restoration) doesn't insert duplicate rows.
    private func persistDailyPlanProfileIfNeeded() {
        guard !didPersist else {
            return
        }
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
        .tidePage(energy: 1)
}
