//
// DayPlanScheduler.swift
// Tempo
//
// Listens for re-plan signals and debounces them into actual
// DayPlannerService.replan() calls. Per
// docs/INTELLIGENCE_REMEDIATION_PLAN.md §9.3.
//
// v1 signals wired:
//   • UIApplication.willEnterForegroundNotification — re-plan when the
//     user returns to the app (cheap; debounced).
//   • .EKEventStoreChanged — re-plan when calendar events change.
//   • .tempoDayPlanReplanRequested — broadcast trigger any subsystem can
//     post (Whoop sync completion, workout logging, meal-eaten off
//     schedule, manual user "re-plan today" tap).
//
// Debounce window is 1.5s so a burst of signals (e.g. EventKit fires
// three .EKEventStoreChanged notifications for one batch edit) collapses
// into a single solver run.
//

import EventKit
import Foundation
import SwiftData
import UIKit

extension Notification.Name {
    /// Posted by any subsystem that just changed a fact the daily plan
    /// depends on. The scheduler observes this and triggers a debounced
    /// replan. Optional `userInfo["reason"]` accepts a `DayPlanReason`
    /// rawValue for telemetry attribution.
    static let tempoDayPlanReplanRequested = Notification.Name("tempo.dayPlan.replanRequested")

    /// Posted when the user changes a Training setting that affects the
    /// nutrition plan (trainingSplit, footballDays). NutritionTabViewModel
    /// observes this and re-generates the active WeeklyMealPlan so the
    /// Plan tab's day-types track the user's real training week.
    static let tempoTrainingSettingsChanged = Notification.Name("tempo.training.settingsChanged")

    /// Posted whenever a meal is logged, marked eaten, or its macros
    /// change (Quick Log, Mark Eaten, substitute, edit eat-time). The
    /// Dashboard observes this to re-run its Fuel quadrant refresh so the
    /// dashboard and the Nutrition tab never show divergent calories /
    /// eat-times. Decouples the two view models without sharing state.
    static let tempoNutritionLogged = Notification.Name("tempo.nutrition.logged")

    /// Posted when a workout's persisted state changes (started, saved/
    /// completed, or a crashed session discarded). The Dashboard observes
    /// this to re-run refreshTrainingStatus so the Move quadrant matches
    /// the Training tab without waiting for a cold refresh. Same
    /// decoupling pattern as tempoNutritionLogged.
    static let tempoWorkoutChanged = Notification.Name("tempo.workout.changed")
}

@MainActor
final class DayPlanScheduler {

    private let service: DayPlannerService
    private var observers: [NSObjectProtocol] = []
    private var debounceTask: Task<Void, Never>?

    init(service: DayPlannerService) {
        self.service = service
        register()
    }
    // No deinit cleanup: NotificationCenter holds the observer tokens via
    // `[weak self]` closures, so when this object deallocates the closures
    // stop having a target and the observers become inert. An explicit
    // `removeObserver` would also work but can't be done from a
    // nonisolated deinit without crossing actor boundaries.

    // MARK: - Wiring

    private func register() {
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The closure is a nonisolated @Sendable context even though
            // queue: .main guarantees main-thread delivery at runtime.
            // Hop explicitly so Swift 6 can prove the actor boundary.
            Task { @MainActor in self?.requestReplan(reason: .userRequested) }
        })

        observers.append(center.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.requestReplan(reason: .calendarChanged) }
        })

        observers.append(center.addObserver(
            forName: .tempoDayPlanReplanRequested,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let reason: DayPlanReason = {
                if let raw = note.userInfo?["reason"] as? String,
                   let mapped = DayPlanReason(rawValue: raw)
                {
                    return mapped
                }
                return .userRequested
            }()
            Task { @MainActor in self?.requestReplan(reason: reason) }
        })
    }

    // MARK: - Debounced replan

    private func requestReplan(reason: DayPlanReason) {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            // 1.5s debounce — burst-collapses EventKit + sync chatter.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self else { return }
            _ = await self.service.replan(reason: reason)
        }
    }

    /// Fire an immediate (non-debounced) replan. Use sparingly — the
    /// "Re-plan today" button in DayPlanView still goes through
    /// `DayPlannerService.replan` directly so the user sees a spinner.
    func replanNow(reason: DayPlanReason = .userRequested) async {
        debounceTask?.cancel()
        _ = await service.replan(reason: reason)
    }
}
