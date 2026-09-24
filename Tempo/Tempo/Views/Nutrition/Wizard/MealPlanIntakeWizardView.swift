//
// MealPlanIntakeWizardView.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import SwiftData
import SwiftUI

struct MealPlanIntakeWizardView: View {
    @State
    private var coordinator: WizardCoordinator
    @State
    private var didSeed = false
    @Environment(\.modelContext)
    private var modelContext

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
        .onAppear(perform: seedIntakeIfNeeded)
    }

    /// Pre-fill from the user's saved answers instead of bare defaults:
    /// persisted wizard prefs, and — when the wizard has never saved an eating
    /// window — the one from onboarding (UserDailyPlanProfile). The call site
    /// only hands us a snapshot, so the seed happens here, once, before the
    /// user touches anything.
    private func seedIntakeIfNeeded() {
        guard !didSeed else { return }
        didSeed = true
        let settings = try? modelContext.fetch(FetchDescriptor<UserSettings>()).first
        let dailyPlan = try? modelContext.fetch(FetchDescriptor<UserDailyPlanProfile>()).first
        coordinator.seed(MealPlanIntake.seeded(settings: settings, dailyPlan: dailyPlan))
    }
}
