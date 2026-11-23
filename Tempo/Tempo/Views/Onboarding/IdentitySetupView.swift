//
// IdentitySetupView.swift
// Tempo
//
// Created by Tempo on 18/05/2026.
//
//

import SwiftUI

// MARK: - Identity Setup View

// "What best describes you?" — single-select identity label. REQUIRED.
// The chosen label persists to UserProfile.identityLabel (via the onboarding
// UserDefaults bridge in ContentView.ensureUserProfile) and is surfaced in
// Settings. Options are the canonical list in OnboardingViewModel.identityLabels.

struct IdentitySetupView: View {
    @Bindable
    var viewModel: OnboardingViewModel

    private let labels = OnboardingViewModel.identityLabels

    var body: some View {
        OnboardingScaffold(
            title: "WHAT BEST DESCRIBES YOU?",
            primaryTitle: "CONTINUE",
            primaryEnabled: viewModel.canContinue,
            primaryAction: { viewModel.advance() }
        ) {
            // Tapping a row sets viewModel.identityLabel; the chosen one shows
            // the accent ring and a check.
            VStack(spacing: Tide.s2) {
                ForEach(labels, id: \.self) { label in
                    OnboardingOptionRow(title: label, isSelected: viewModel.identityLabel == label) {
                        viewModel.identityLabel = label
                        HapticManager.lightImpact()
                    }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    IdentitySetupView(viewModel: vm)
        .tidePage(energy: 1)
}
