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
            case .temporaryExclusions:
                TemporaryExclusionsStepView(coordinator: coordinator)
            case .recoveryOverride:
                RecoveryOverrideStepView(coordinator: coordinator)
            case .review:
                ReviewStepView(coordinator: coordinator)
            }
        }
        .interactiveDismissDisabled()
        .onAppear(perform: seedIntakeIfNeeded)
    }

    /// Pre-fill from the user's saved answers instead of bare defaults (the
    /// saved cooking days / recovery pref, or this week's answers if the
    /// wizard already ran). The call site only hands us a snapshot, so the
    /// seed happens here, once, before the user touches anything.
    private func seedIntakeIfNeeded() {
        guard !didSeed else { return }
        didSeed = true
        let settings = try? modelContext.fetch(FetchDescriptor<UserSettings>()).first
        let dailyPlan = UserDailyPlanProfile.current(in: modelContext)
        coordinator.seed(MealPlanIntake.seeded(settings: settings, dailyPlan: dailyPlan))
    }
}
