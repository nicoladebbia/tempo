//
// MealPlanIntakeWizardView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftUI

struct MealPlanIntakeWizardView: View {
    @State
    private var coordinator: WizardCoordinator

    init(
        snapshot: WizardLaunchSnapshot,
        onComplete: @escaping (MealPlanIntake) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _coordinator = State(
            initialValue: WizardCoordinator(
                snapshot: snapshot,
                onComplete: onComplete,
                onCancel: onCancel
            )
        )
    }

    var body: some View {
        Group {
            switch coordinator.currentStep {
            case .cookingCapacity:
                CookingCapacityStepView(coordinator: coordinator)
            case .leftoverTolerance:
                LeftoverToleranceStepView(coordinator: coordinator)
            case .eatingWindow:
                EatingWindowStepView(coordinator: coordinator)
            case .pantryGap:
                PantryGapStepView(coordinator: coordinator)
            case .groceryIntent:
                GroceryIntentStepView(coordinator: coordinator)
            case .recoveryOverride:
                RecoveryOverrideStepView(coordinator: coordinator)
            case .temporaryExclusions:
                TemporaryExclusionsStepView(coordinator: coordinator)
            case .review:
                ReviewStepView(coordinator: coordinator)
            }
        }
        .interactiveDismissDisabled()
    }
}
