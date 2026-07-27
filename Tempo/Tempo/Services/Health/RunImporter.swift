//
// RunImporter.swift
// Tempo
//
// §13 running module — mirrors HealthKit running workouts into RunSession
// rows so the run history has real data without any in-app GPS tracking
// (Watch / Whoop / any running app that writes to Health becomes a source).
// Idempotent: a run is keyed by its exact start date; re-imports skip
// existing rows.
//

import Foundation
import SwiftData

enum RunImporter {
    /// Sub-100 m "runs" are GPS blips / accidental taps — not history.
    private static let minimumMeters: Double = 100

    /// Map one HealthKit sample to a RunSession. nil for non-runs and
    /// distance-less rows (a treadmill run without distance still imports —
    /// pace just stays nil — but a zero-length outdoor blip doesn't).
    static func runSession(from sample: WorkoutSample) -> RunSession? {
        guard sample.workoutType == "run" else {
            return nil
        }
        let meters = sample.distanceMeters ?? 0
        guard meters >= minimumMeters else {
            return nil
        }
        let duration = max(1, Int(sample.endDate.timeIntervalSince(sample.startDate)))
        let pace = Double(duration) / (meters / 1000)
        return RunSession(
            date: sample.startDate,
            distanceMeters: meters,
            durationSeconds: duration,
            avgPaceSecondsPerKm: pace,
            avgHR: sample.averageHeartRate,
            maxHR: sample.maxHeartRate,
            calories: sample.activeCalories > 0 ? sample.activeCalories : nil
        )
    }

    /// Insert the sample as a RunSession unless one already exists at the
    /// same start date. Returns true when a row was inserted.
    @MainActor
    static func upsert(_ sample: WorkoutSample, modelContext: ModelContext) -> Bool {
        guard let run = runSession(from: sample) else {
            return false
        }
        let start = sample.startDate
        let existing = FetchDescriptor<RunSession>(
            predicate: #Predicate { $0.date == start }
        )
        if let count = try? modelContext.fetchCount(existing), count > 0 {
            return false
        }
        modelContext.insert(run)
        return true
    }

    /// Sweep the trailing window of HealthKit workouts and mirror every run.
    /// Returns the number of newly imported rows.
    @MainActor
    static func importRuns(
        days: Int = 30,
        healthKit: any HealthKitServiceProtocol,
        modelContext: ModelContext
    ) async -> Int {
        let cal = Calendar.current
        var imported = 0
        for offset in 0 ..< max(1, days) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()),
                  let samples = try? await healthKit.fetchWorkouts(for: day)
            else {
                continue
            }
            for sample in samples where upsert(sample, modelContext: modelContext) {
                imported += 1
            }
        }
        if imported > 0 {
            try? modelContext.save()
        }
        return imported
    }
}
