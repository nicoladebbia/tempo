//
// BackgroundSyncService.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import BackgroundTasks
import Foundation
import os

final class BackgroundSyncService: @unchecked Sendable {
    static let healthKitSyncID = "com.tempo.healthkit-sync"
    static let dataSyncID = "com.tempo.data-sync"
    static let dailyResetID = "com.tempo.daily-reset"

    private let logger = Logger(subsystem: "app.tempo", category: "BackgroundSync")

    /// Hook the app installs at startup so the daily-reset BG task can run
    /// end-of-day finalization (streak roll-over, day-failed scoring) without
    /// the user having to open the app. Must be safe to invoke from a
    /// background thread; see TempoApp.swift for the SwiftData wiring.
    var dailyResetHandler: (@Sendable () async -> Void)?

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.healthKitSyncID,
            using: nil
        ) { [weak self] task in
            self?.handleHealthKitSync(task: task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.dataSyncID,
            using: nil
        ) { [weak self] task in
            self?.handleDataSync(task: task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.dailyResetID,
            using: nil
        ) { [weak self] task in
            self?.handleDailyReset(task: task as! BGProcessingTask)
        }

        logger.debug("Background tasks registered")
    }

    func scheduleNextSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.dataSyncID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.debug("Scheduled next background sync")
        } catch {
            logger.error("Failed to schedule background sync: \(error)")
        }
    }

    /// Schedule the next daily-reset run to fire after the upcoming local midnight.
    /// iOS may delay the actual launch by hours; that's acceptable for
    /// streak roll-over because the handler computes against `Date()` at
    /// execution time, not the scheduled instant.
    func scheduleDailyReset() {
        let cal = Calendar.current
        let now = Date()
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        // Aim for 5 minutes past midnight to stay clear of date arithmetic edges.
        let runAfter = cal.date(byAdding: .minute, value: 5, to: tomorrow) ?? tomorrow

        let request = BGProcessingTaskRequest(identifier: Self.dailyResetID)
        request.earliestBeginDate = runAfter
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.debug("Scheduled daily reset for \(runAfter, privacy: .public)")
        } catch {
            logger.error("Failed to schedule daily reset: \(error)")
        }
    }

    // MARK: - Handlers

    private func handleHealthKitSync(task: BGAppRefreshTask) {
        logger.debug("Handling HealthKit background sync")
        task.setTaskCompleted(success: true)
        scheduleNextSync()
    }

    private func handleDataSync(task: BGAppRefreshTask) {
        logger.debug("Handling data background sync")
        task.setTaskCompleted(success: true)
        scheduleNextSync()
    }

    private func handleDailyReset(task: BGProcessingTask) {
        logger.debug("Handling daily reset")
        // Always re-arm the next reset before doing work so an exception
        // here doesn't leave the schedule empty.
        scheduleDailyReset()

        guard let handler = dailyResetHandler else {
            task.setTaskCompleted(success: true)
            return
        }

        task.expirationHandler = {
            // OS is reclaiming time; fall through to completion.
        }

        // BGProcessingTask is not Sendable, but its `setTaskCompleted` is safe
        // to invoke off the main thread. Wrap it in a Sendable shim via an
        // unchecked-Sendable holder so strict concurrency doesn't reject the
        // closure capture.
        struct TaskHolder: @unchecked Sendable {
            let task: BGProcessingTask
        }
        let holder = TaskHolder(task: task)
        Task.detached {
            await handler()
            holder.task.setTaskCompleted(success: true)
        }
    }
}
