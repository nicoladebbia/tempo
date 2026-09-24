//
// WizardCoordinator.swift
// Tempo
//
// Created by Tempo on 11/05/2026.
//
//

import Foundation
import SwiftUI

// MARK: - WizardStep

enum WizardStep: Int, CaseIterable, Identifiable, Sendable {
    case cookingCapacity
    case leftoverTolerance
    case eatingWindow
    case pantryGap
    case groceryIntent
    case recoveryOverride
    case temporaryExclusions
    case review

    var id: Int {
        rawValue
    }

    var titleKey: String {
        switch self {
        case .cookingCapacity: "nutrition.wizard.cookingCapacity.title"
        case .leftoverTolerance: "nutrition.wizard.leftoverTolerance.title"
        case .eatingWindow: "nutrition.wizard.eatingWindow.title"
        case .pantryGap: "nutrition.wizard.pantryGap.title"
        case .groceryIntent: "nutrition.wizard.groceryIntent.title"
        case .recoveryOverride: "nutrition.wizard.recoveryOverride.title"
        case .temporaryExclusions: "nutrition.wizard.temporaryExclusions.title"
        case .review: "nutrition.wizard.review.title"
        }
    }
}

// MARK: - WizardCoordinator

@Observable
@MainActor
final class WizardCoordinator {
    // MARK: - State

    private(set) var currentStep: WizardStep = .cookingCapacity
    private(set) var visibleSteps: [WizardStep]
    var intake: MealPlanIntake
    let snapshot: WizardLaunchSnapshot

    private let onComplete: (MealPlanIntake) -> Void
    private let onCancel: () -> Void

    // MARK: - Init

    init(
        snapshot: WizardLaunchSnapshot,
        initialIntake: MealPlanIntake = .default,
        onComplete: @escaping (MealPlanIntake) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.snapshot = snapshot
        self.intake = initialIntake
        self.onComplete = onComplete
        self.onCancel = onCancel
        self.visibleSteps = []
        self.visibleSteps = Self.computeVisibleSteps(snapshot: snapshot, intake: initialIntake)
        self.currentStep = visibleSteps.first ?? .review
    }

    // MARK: - Step Visibility

    static func computeVisibleSteps(
        snapshot: WizardLaunchSnapshot,
        intake: MealPlanIntake
    ) -> [WizardStep] {
        var steps: [WizardStep] = [.cookingCapacity, .leftoverTolerance, .eatingWindow]

        if snapshot.pantryNeedsAttention {
            steps.append(.pantryGap)
            // groceryIntent only fires when user said they need a run
            if intake.groceryIntent?.willShopThisWeek == true {
                steps.append(.groceryIntent)
            }
        }

        if snapshot.hasWhoop {
            steps.append(.recoveryOverride)
        }

        steps.append(.temporaryExclusions)
        steps.append(.review)
        return steps
    }

    /// Recompute visibleSteps after intake changes (e.g. user toggled pantryGap → showing groceryIntent).
    private func refreshVisibility() {
        let updated = Self.computeVisibleSteps(snapshot: snapshot, intake: intake)
        visibleSteps = updated
    }

    /// Replace the starting answers (wizard pre-fill). Only valid before the
    /// user has moved past the first step — later it would clobber edits.
    func seed(_ seededIntake: MealPlanIntake) {
        guard currentStep == visibleSteps.first else { return }
        intake = seededIntake
        refreshVisibility()
    }

    // MARK: - Navigation

    var progress: Double {
        guard !visibleSteps.isEmpty else {
            return 1
        }
        guard let idx = visibleSteps.firstIndex(of: currentStep) else {
            return 0
        }
        return Double(idx + 1) / Double(visibleSteps.count)
    }

    var canGoBack: Bool {
        guard let idx = visibleSteps.firstIndex(of: currentStep) else {
            return false
        }
        return idx > 0
    }

    var isLastStep: Bool {
        currentStep == .review
    }

    func advance() {
        refreshVisibility()
        guard let idx = visibleSteps.firstIndex(of: currentStep) else {
            return
        }
        let nextIdx = idx + 1
        if nextIdx < visibleSteps.count {
            currentStep = visibleSteps[nextIdx]
        }
    }

    func goBack() {
        guard let idx = visibleSteps.firstIndex(of: currentStep), idx > 0 else {
            return
        }
        currentStep = visibleSteps[idx - 1]
    }

    func cancel() {
        onCancel()
    }

    func submit() {
        onComplete(intake)
    }
}
