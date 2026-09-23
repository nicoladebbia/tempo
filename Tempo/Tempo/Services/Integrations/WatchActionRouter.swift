//
// WatchActionRouter.swift
// Tempo
//
// The one app-level handler for every Apple Watch quick action, registered at
// launch. Each action runs the same operation the phone UI uses (complete a
// non-negotiable, mark a meal eaten, focus timer, start workout; logSet goes
// to TrainingViewModel). Returns whether it applied — the watch plays its
// success haptic only on that acknowledgement.
//

import Foundation
import SwiftData

@MainActor
final class WatchActionRouter {
    private let accountabilityEngine: AccountabilityEngine
    private let notifications: any NotificationServiceProtocol

    /// Set once by `ServiceContainer.configure(modelContext:)` at launch
    /// (`TempoApp.init`, right after the ModelContainer is created). Optional
    /// so tests / mock containers that never configure it fail closed
    /// (every handler no-ops) instead of crashing.
    private var modelContext: ModelContext?

    /// Owned by Training (`TodayWorkoutView.task`), registered exactly as
    /// before. Kept separate from the other actions because it needs the
    /// LIVE `TrainingViewModel` instance (today's loaded plan, weight unit,
    /// etc.) — the other actions are fine constructing a disposable
    /// view model against fresh SwiftData rows.
    private var logSetHandler: (@MainActor (WatchActionPayload) -> Bool)?
    private var pendingLogSets: [WatchActionPayload] = []

    /// Kept alive for the duration of a wrist-started focus session — its
    /// internal countdown `Task` and Live Activity update loop capture
    /// `self` weakly, so nothing else retaining it would silently kill the
    /// timer and drop the eventual `savePartialSession` study-minutes
    /// write. Cleared when the session stops or is cancelled.
    private var activeFocusViewModel: AccountabilityViewModel?

    init(
        accountabilityEngine: AccountabilityEngine,
        notifications: any NotificationServiceProtocol
    ) {
        self.accountabilityEngine = accountabilityEngine
        self.notifications = notifications
    }

    /// Called once at launch, after the ModelContainer exists (`TempoApp.init`).
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Logged Set (owned by Training)

    /// Registered by `TodayWorkoutView.task`. Replays anything that arrived
    /// (and buffered here) before Training ever loaded.
    func setLogSetHandler(_ handler: @escaping @MainActor (WatchActionPayload) -> Bool) {
        logSetHandler = handler
        let pending = pendingLogSets
        pendingLogSets = []
        for action in pending {
            _ = handler(action)
        }
    }

    // MARK: - Dispatch

    /// Returns whether the action was actually applied — travels back to
    /// the watch as the message reply so its success haptic only fires once
    /// this is `true` (§22 — no optimistic success haptics).
    @discardableResult
    func handle(_ action: WatchActionPayload) -> Bool {
        switch action.action {
        case .logSet:
            routeLogSet(action)
        case .markNonNegotiableDone:
            markNonNegotiableDone(id: action.payload["id"])
        case .markMealEaten:
            markMealEaten(id: action.payload["id"])
        case .startFocusTimer:
            startFocusTimer(durationSeconds: action.payload["duration"].flatMap(Int.init))
        case .pauseFocusTimer:
            pauseFocusTimer()
        case .resumeFocusTimer:
            resumeFocusTimer()
        case .stopFocusTimer:
            stopFocusTimer()
        case .startWorkout:
            startWorkout()
        }
    }

    private func routeLogSet(_ action: WatchActionPayload) -> Bool {
        guard let logSetHandler else {
            pendingLogSets.append(action)
            return false
        }
        return logSetHandler(action)
    }

    // MARK: - Non-Negotiables

    /// Same operation as tapping a non-negotiable row in Lockdown —
    /// `AccountabilityViewModel.completeItem`, via the shared engine so
    /// streak/unlock logic matches exactly.
    private func markNonNegotiableDone(id: String?) -> Bool {
        guard let modelContext, let id, let uuid = UUID(uuidString: id) else {
            return false
        }
        let viewModel = AccountabilityViewModel(engine: accountabilityEngine)
        viewModel.loadToday(modelContext: modelContext)
        guard let progress = viewModel.progressItems.first(where: { $0.nonNegotiable?.id == uuid }),
              !progress.isCompleted
        else {
            return false
        }
        viewModel.completeItem(progress, modelContext: modelContext)
        return true
    }

    // MARK: - Meals

    /// Same operation as tapping Mark Eaten in Nutrition —
    /// `NutritionTabViewModel.markMealEaten` (meal shift + macro rebalance
    /// included). A fresh disposable view model is the established pattern
    /// for this exact call (see `MealDetailView`'s `undoMealEaten`).
    private func markMealEaten(id: String?) -> Bool {
        guard let modelContext, let id, let uuid = UUID(uuidString: id) else {
            return false
        }
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { $0.id == uuid }
        )
        guard let meal = (try? modelContext.fetch(descriptor))?.first,
              meal.status != .eaten
        else {
            return false
        }
        NutritionTabViewModel().markMealEaten(meal, modelContext: modelContext, notifications: notifications)
        return true
    }

    // MARK: - Focus Timer

    private func startFocusTimer(durationSeconds: Int?) -> Bool {
        guard let modelContext, activeFocusViewModel == nil else {
            return false
        }
        let viewModel = AccountabilityViewModel(engine: accountabilityEngine)
        viewModel.loadToday(modelContext: modelContext)
        viewModel.configureFocusTimer(duration: TimeInterval(durationSeconds ?? 1500))
        viewModel.startFocusSession(modelContext: modelContext)
        activeFocusViewModel = viewModel
        return true
    }

    private func pauseFocusTimer() -> Bool {
        guard let viewModel = activeFocusViewModel else {
            return false
        }
        viewModel.pauseFocus()
        return true
    }

    private func resumeFocusTimer() -> Bool {
        guard let modelContext, let viewModel = activeFocusViewModel else {
            return false
        }
        viewModel.resumeFocus(modelContext: modelContext)
        return true
    }

    private func stopFocusTimer() -> Bool {
        guard let modelContext, let viewModel = activeFocusViewModel else {
            return false
        }
        viewModel.cancelFocus(modelContext: modelContext)
        activeFocusViewModel = nil
        return true
    }

    // MARK: - Workout

    /// Real, minimal equivalent of "start workout": flips today's plan to
    /// `.inProgress` — the same field-level effect `applyWatchSetLog`
    /// already performs on the FIRST logged set. Deliberately does not
    /// touch ExerciseHistory / set completion (Training-owned territory).
    private func startWorkout() -> Bool {
        guard let modelContext else {
            return false
        }
        let today = Calendar.current.startOfDay(for: Date())
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) else {
            return false
        }
        let descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate<WorkoutPlan> { $0.date >= today && $0.date < tomorrow }
        )
        guard let plans = try? modelContext.fetch(descriptor),
              let plan = plans.first(where: { $0.status == .planned })
        else {
            return false
        }
        plan.status = .inProgress
        plan.startedAt = plan.startedAt ?? Date()
        guard (try? modelContext.save()) != nil else {
            return false
        }
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        return true
    }
}
