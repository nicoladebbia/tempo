//
// WhoopConnectView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Whoop Connect View

// Per WIREFRAMES.md Screen 47 — Whoop connection during onboarding. OPTIONAL.
// Per STATE_MACHINES.md Section 10 — Connected or Skip.

struct WhoopConnectView: View {
    @Bindable
    var viewModel: OnboardingViewModel
    @Environment(ServiceContainer.self)
    private var services
    @State
    private var isConnecting = false
    @State
    private var errorMessage: String?

    var body: some View {
        OnboardingScaffold(
            title: "YOUR BODY TALKS.\nLET'S LISTEN.",
            primaryTitle: isConnecting ? "CONNECTING..." : "CONNECT WHOOP",
            primaryEnabled: !isConnecting,
            primaryAction: {
                Task {
                    isConnecting = true
                    errorMessage = nil
                    do {
                        try await services.whoop.connect()
                        viewModel.whoopConnected = true
                        viewModel.advance()
                    } catch {
                        errorMessage = "Connection failed. You can try again or skip."
                        isConnecting = false
                    }
                }
            },
            skipAction: { viewModel.skip() },
            centered: true
        ) {
            OnboardingHeroTile(systemName: "waveform.path.ecg", tint: Color.tempoSuccess)

            VStack(alignment: .leading, spacing: Tide.s3) {
                OnboardingBenefitRow(systemImage: "heart.fill", text: "Recovery scores + HRV", tint: Color.tempoSuccess)
                OnboardingBenefitRow(systemImage: "moon.fill", text: "Sleep analysis", tint: Color.tempoSuccess)
                OnboardingBenefitRow(systemImage: "flame.fill", text: "Strain tracking", tint: Color.tempoSuccess)
                OnboardingBenefitRow(
                    systemImage: "arrow.triangle.2.circlepath",
                    text: "Auto-adjusted workouts",
                    tint: Color.tempoSuccess
                )
            }
            .onboardingCard()

            if let errorMessage {
                Text(errorMessage)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    WhoopConnectView(viewModel: vm)
        .tidePage(energy: 1)
        .environment(ServiceContainer.mock())
}
