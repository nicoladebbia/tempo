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

    // MARK: - Handlers (placeholders)

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
        task.setTaskCompleted(success: true)
    }
}
