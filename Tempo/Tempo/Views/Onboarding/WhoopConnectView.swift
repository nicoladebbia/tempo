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
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            Text("YOUR BODY TALKS.\nLET'S LISTEN.")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 60))
                .foregroundStyle(Color.tempoSuccess)

            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                benefitRow(icon: "heart.fill", text: "Recovery scores + HRV")
                benefitRow(icon: "moon.fill", text: "Sleep analysis")
                benefitRow(icon: "flame.fill", text: "Strain tracking")
                benefitRow(icon: "arrow.triangle.2.circlepath", text: "Auto-adjusted workouts")
            }
            .padding(.horizontal, TempoSpacing.xxl)

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.tempoError)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TempoSpacing.xl)
            }

            OnboardingPrimaryButton(title: isConnecting ? "CONNECTING..." : "CONNECT WHOOP", enabled: !isConnecting) {
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
            }

            OnboardingSkipButton { viewModel.skip() }

            Spacer().frame(height: TempoSpacing.xxxl)
        }
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: TempoSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.tempoSuccess)
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

    WhoopConnectView(viewModel: vm)
        .background(Color.black)
        .preferredColorScheme(.dark)
}
