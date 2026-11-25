//
// GoalSetupView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Goal Setup View

// Per WIREFRAMES.md Screen 46 — "What are you fighting for?". One question: the primary goal.
// REQUIRED (the goal must be set). Everything else is asked later, where it is needed.
//
// The question is "what are you fighting for?", so the answers are big cards with a symbol
// each, not a list.

struct GoalSetupView: View {
    @Bindable
    var viewModel: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(
            title: String(localized: "WHAT ARE YOU\nFIGHTING FOR?"),
            subtitle: String(localized: "Pick one. You can change it in Settings."),
            primaryTitle: String(localized: "CONTINUE"),
            primaryEnabled: viewModel.canContinue,
            primaryAction: { viewModel.advance() }
        ) {
            // One card each, the last one across the row.
            OnboardingChoiceGrid(items: PrimaryGoal.allCases) { goal in
                OnboardingChoiceCard(
                    title: goal.title,
                    subtitle: goal.detail,
                    systemImage: goal.icon,
                    isSelected: viewModel.primaryGoal == goal
                ) {
                    viewModel.primaryGoal = goal
                }
            }
        }
    }
}

#Preview {
    @Previewable @State
    var vm = OnboardingViewModel()

    GoalSetupView(viewModel: vm)
        .tidePage(energy: 1)
}
