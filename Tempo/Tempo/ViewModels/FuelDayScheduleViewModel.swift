//
// FuelDayScheduleViewModel.swift
// Tempo
//
// Created by Tempo on 13/05/2026.
//

import Foundation
import SwiftData

// MARK: - FuelDayScheduleViewModel

/// Powers the meal list inside `FuelQuadrantDetailView`. Combines today's
/// `PlannedMeal`s (SwiftData) with two intelligence layers:
///
/// 1. **Whoop-adaptive shift** — actual wake time (HealthKit `SleepData`)
///    vs the user's planned wake time (`UserSettings.wakeTimeMinutes`).
///    The delta is applied uniformly to every meal's displayed time.
///    The SwiftData store is never mutated.
///
/// 2. **EventKit conflict detection** — non-all-day calendar events for
///    today are reduced to `BusyBlock`s and matched against each meal's
///    post-shift time. A 15-minute edge window flags meals scheduled
///    too close to either side of a busy block.
///
/// All shape/computation logic lives in `FuelMealScheduleAnnotator` so this
/// VM stays a thin orchestration layer.
@Observable
@MainActor
final class FuelDayScheduleViewModel {
    // MARK: - State

    private(set) var rows: [FuelMealRow] = []
    private(set) var shiftMinutes: Int = 0
    private(set) var lastError: String?

    // MARK: - Dependencies

    private let healthKit: any HealthKitServiceProtocol
    private let calendar: any CalendarServiceProtocol

    init(healthKit: any HealthKitServiceProtocol, calendar: any CalendarServiceProtocol) {
        self.healthKit = healthKit
        self.calendar = calendar
    }

    /// Holds the in-flight refresh so a fast re-entry (pull-to-refresh +
    /// re-appear) doesn't let a stale completion overwrite newer data.
    private var refreshTask: Task<Void, Never>?

    // MARK: - Refresh

    /// Pulls today's planned meals, actual wake, and busy blocks; produces the
    /// annotated rows on the main actor. Non-fatal: any one source failing
    /// degrades to "no shift" / "no conflicts" rather than blocking the list.
    func refresh(modelContext: ModelContext, today: Date = Date()) async {
        refreshTask?.cancel()
        let task: Task<Void, Never> = Task { [weak self] in
            await self?.performRefresh(modelContext: modelContext, today: today)
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh(modelContext: ModelContext, today: Date) async {
        lastError = nil

        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: today)
        let tomorrowStart = cal.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart

        // 1. Today's PlannedMeals (sorted by mealNumber for stable order).
        let mealDescriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= todayStart && meal.dayDate < tomorrowStart
            },
            sortBy: [SortDescriptor(\.mealNumber)]
        )
        let meals = (try? modelContext.fetch(mealDescriptor)) ?? []

        // 2. Planned wake (defaults to 07:00 = 420 if no settings yet).
        let settingsDescriptor = FetchDescriptor<UserSettings>()
        let plannedWakeMinutes = (try? modelContext.fetch(settingsDescriptor).first?.wakeTimeMinutes) ?? 420

        // 3. Actual wake from HealthKit (non-fatal).
        let actualWake: Date? = await {
            do {
                let sleep = try await healthKit.fetchSleepAnalysis(for: today)
                return sleep.wakeTime
            } catch {
                return nil
            }
        }()

        // 4. Today's busy blocks from EventKit (non-fatal; skips all-day events).
        let busyBlocks: [BusyBlock] = await {
            let range = DateInterval(start: todayStart, end: tomorrowStart)
            do {
                let events = try await calendar.fetchEvents(for: range)
                return events
                    .filter { !$0.isAllDay }
                    .map { BusyBlock(start: $0.startDate, end: $0.endDate, title: $0.title, location: $0.location) }
            } catch {
                return []
            }
        }()

        let annotated = FuelMealScheduleAnnotator.annotate(
            meals: meals,
            plannedWakeMinutes: plannedWakeMinutes,
            actualWakeTime: actualWake,
            busyBlocks: busyBlocks,
            calendar: cal
        )
        rows = annotated
        shiftMinutes = annotated.first?.shiftMinutes ?? 0
    }
}
