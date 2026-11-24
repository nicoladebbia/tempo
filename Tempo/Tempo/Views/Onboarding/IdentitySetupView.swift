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
//
// Twenty answers, so a dense grid: two to a row, each with its own symbol,
// the chosen one lit.

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
            // Tapping a card sets viewModel.identityLabel; the chosen one shows
            // the accent ring and a lit symbol.
            OnboardingChoiceGrid(items: labels, stretchesLast: false) { label in
                OnboardingChoiceCard(
                    title: label,
                    systemImage: Self.symbol(for: label),
                    isSelected: viewModel.identityLabel == label,
                    layout: .compact
                ) {
                    viewModel.identityLabel = label
                    HapticManager.lightImpact()
                }
            }
        }
    }

    /// A symbol for each label in `OnboardingViewModel.identityLabels`.
    private static func symbol(for label: String) -> String {
        switch label {
        case "Athlete": "figure.run"
        case "Student": "graduationcap.fill"
        case "Student-Athlete": "figure.run.circle.fill"
        case "Coach": "megaphone.fill"
        case "Personal Trainer": "figure.strengthtraining.traditional"
        case "Bodybuilder": "dumbbell.fill"
        case "Runner": "figure.run.treadmill"
        case "Cyclist": "bicycle"
        case "Swimmer": "figure.pool.swim"
        case "Combat Sports": "figure.boxing"
        case "Team Sport Player": "sportscourt.fill"
        case "Weekend Warrior": "figure.hiking"
        case "Military / First Responder": "shield.fill"
        case "Office Worker": "briefcase.fill"
        case "Remote Worker": "laptopcomputer"
        case "Entrepreneur": "lightbulb.fill"
        case "Artist / Creative": "paintpalette.fill"
        case "Parent": "figure.2.and.child.holdinghands"
        case "Retiree": "sun.horizon.fill"
        case "General Fitness": "heart.fill"
        default: "person.fill"
        }
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    IdentitySetupView(viewModel: vm)
        .tidePage(energy: 1)
}
