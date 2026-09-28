//
// WatchGuidedRunHeartRateService.swift
// Tempo
//
// Guided run mode — Apple Watch run mode §2: runs a real `HKWorkoutSession`
// (running) for the duration of a mirrored guided run so heart rate keeps
// sampling from the wrist even with the screen off, and streams every new
// BPM reading to the phone as an ordinary `.guidedRunHeartRate` quick action
// (§22 pattern — no new wire format). The phone is what actually persists
// samples into the summary; this is purely the live sensor + relay.
//
// Never touches anything if HealthKit isn't authorized — a guided run works
// exactly as well without a Watch or without HR permission, just with no
// live BPM shown.
//

import Foundation
import HealthKit

// MARK: - WatchGuidedRunHeartRateService

@MainActor
@Observable
final class WatchGuidedRunHeartRateService: NSObject {
    private(set) var currentBPM: Double?
    private(set) var isRunning = false

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    /// Injected so tests can assert the relay without a real WCSession.
    var onSample: (Double) -> Void = { bpm in
        WatchConnectivityService.shared.sendAction(.guidedRunHeartRate, payload: ["bpm": String(bpm)])
    }

    /// Starts the workout session — a no-op if already running or HealthKit
    /// isn't available/authorized on this Watch.
    func start() {
        guard !isRunning, HKHealthStore.isHealthDataAvailable() else {
            return
        }
        let heartRateType = HKQuantityType(.heartRate)
        healthStore.requestAuthorization(toShare: [HKQuantityType.workoutType()], read: [heartRateType]) { [weak self] granted, _ in
            guard granted else {
                return
            }
            Task { @MainActor in
                self?.beginSession()
            }
        }
    }

    private func beginSession() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        guard let session = try? HKWorkoutSession(healthStore: healthStore, configuration: configuration) else {
            return
        }
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self

        self.session = session
        self.builder = builder
        isRunning = true

        let now = Date()
        session.startActivity(with: now)
        builder.beginCollection(withStart: now) { _, _ in }
    }

    /// Ends the workout session — call when the mirrored run ends or the
    /// Watch app is dismissed.
    func stop() {
        guard isRunning, let session else {
            return
        }
        isRunning = false
        currentBPM = nil
        session.end()
        let builderToFinish = builder
        builder?.endCollection(withEnd: Date()) { _, _ in
            builderToFinish?.finishWorkout { _, _ in }
        }
        self.session = nil
        builder = nil
    }
}

// MARK: HKWorkoutSessionDelegate

extension WatchGuidedRunHeartRateService: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _: HKWorkoutSession,
        didChangeTo _: HKWorkoutSessionState,
        from _: HKWorkoutSessionState,
        date _: Date
    ) {}

    nonisolated func workoutSession(_: HKWorkoutSession, didFailWithError _: Error) {
        // No live HR — the guided-run UI just shows nothing for HR/zone.
    }
}

// MARK: HKLiveWorkoutBuilderDelegate

extension WatchGuidedRunHeartRateService: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRateType),
              let statistics = workoutBuilder.statistics(for: heartRateType),
              let quantity = statistics.mostRecentQuantity()
        else {
            return
        }
        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = quantity.doubleValue(for: unit)
        Task { @MainActor in
            self.currentBPM = bpm
            self.onSample(bpm)
        }
    }
}
