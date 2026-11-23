//
// HealthKitPermissionView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - HealthKit Permission View (Onboarding)

// Per STATE_MACHINES.md Section 10 — Request HealthKit permissions. OPTIONAL.

struct HealthKitPermissionView: View {
    @Bindable
    var viewModel: OnboardingViewModel
    @Environment(ServiceContainer.self)
    private var services

    var body: some View {
        OnboardingScaffold(
            title: "LET'S CONNECT\nYOUR HEALTH DATA.",
            primaryTitle: "ALLOW HEALTHKIT",
            primaryAction: {
                Task {
                    try? await services.healthKit.requestAuthorization()
                    viewModel.healthkitGranted = true
                    viewModel.advance()
                }
            },
            skipAction: { viewModel.skip() },
            centered: true
        ) {
            OnboardingHeroTile(systemName: "heart.text.square.fill", tint: Tide.protein)

            VStack(alignment: .leading, spacing: Tide.s3) {
                OnboardingBenefitRow(systemImage: "figure.walk", text: "Steps & active calories", tint: Tide.protein)
                OnboardingBenefitRow(systemImage: "heart.fill", text: "Heart rate data", tint: Tide.protein)
                OnboardingBenefitRow(systemImage: "bed.double.fill", text: "Sleep tracking", tint: Tide.protein)
                OnboardingBenefitRow(systemImage: "flame.fill", text: "Workout integration", tint: Tide.protein)
            }
            .onboardingCard()

            OnboardingNote(
                "Your health data stays on your device. Tempo never uploads raw HealthKit data.",
                systemImage: "lock.fill"
            )
        }
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    HealthKitPermissionView(viewModel: vm)
        .tidePage(energy: 1)
        .environment(ServiceContainer.mock())
}
