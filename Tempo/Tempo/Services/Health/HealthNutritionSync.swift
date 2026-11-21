//
// HealthNutritionSync.swift
// Tempo
//
// Keeps Apple Health's food log in step with what the user ate in Tempo: one
// Health food entry per eaten meal (kcal, protein, carbs, fat) named after the
// meal. Eating a meal writes it, editing portions updates it (higher sync
// version), undo / delete / un-eat removes it, restoring re-adds it.
//
// It never reads Health. Each pass compares today's eaten meals
// (`CanonicalMeals.eatenMeals`) with a small local record of what Tempo last
// wrote (meal id -> fingerprint + version) and only touches the difference.
// A write Health refused (not authorised) isn't recorded, so it is retried on
// the next pass instead of silently lost; passes are debounced so a burst of
// edits is one pass.
//

import Foundation
import OSLog
import SwiftData

@MainActor
final class HealthNutritionSync {
    struct Record: Codable, Equatable {
        var fingerprint: String
        var version: Int
        var day: Date
    }

    static let defaultsKey = "tempo.healthNutritionSync.records.v1"
    static let syncPrefix = "tempo-meal-"

    private let healthKit: any HealthKitServiceProtocol
    private let context: ModelContext
    private let defaults: UserDefaults
    private let debounce: Duration
    private let logger = Logger(subsystem: "app.tempo.Tempo", category: "healthNutritionSync")

    private var observer: NSObjectProtocol?
    private var pending: Task<Void, Never>?
    private var isReconciling = false
    private var needsAnotherPass = false

    init(
        healthKit: any HealthKitServiceProtocol,
        context: ModelContext,
        defaults: UserDefaults = .standard,
        debounce: Duration = .seconds(2)
    ) {
        self.healthKit = healthKit
        self.context = context
        self.defaults = defaults
        self.debounce = debounce
    }

    /// Start observing `.tempoNutritionLogged` and run one initial pass.
    /// Safe to call more than once.
    func start() {
        guard observer == nil else {
            return
        }
        observer = NotificationCenter.default.addObserver(
            forName: .tempoNutritionLogged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReconcile() }
        }
        scheduleReconcile()
    }

    func scheduleReconcile() {
        pending?.cancel()
        let wait = debounce
        pending = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else {
                return
            }
            await self?.reconcile()
        }
    }

    // MARK: - Reconcile

    /// One pass for today plus every earlier day Tempo still has a record for.
    func reconcile(now: Date = Date()) async {
        if isReconciling {
            needsAnotherPass = true
            return
        }
        isReconciling = true
        defer { isReconciling = false }

        repeat {
            needsAnotherPass = false
            await reconcileOnce(now: now)
        } while needsAnotherPass
    }

    private func reconcileOnce(now: Date) async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var records = loadRecords()

        // Forget records older than two weeks (leaves Health untouched).
        if let cutoff = calendar.date(byAdding: .day, value: -14, to: today) {
            records = records.filter { $0.value.day >= cutoff }
        }

        var days: Set<Date> = [today]
        for record in records.values {
            days.insert(calendar.startOfDay(for: record.day))
        }

        var seen = Set<String>()
        for day in days {
            for meal in CanonicalMeals.eatenMeals(on: day, in: context) {
                let key = meal.id.uuidString
                seen.insert(key)
                let fingerprint = Self.fingerprint(of: meal)
                if records[key]?.fingerprint == fingerprint {
                    continue
                }
                let version = max((records[key]?.version ?? 0) + 1, Int(now.timeIntervalSince1970 * 1000))
                let sample = NutritionSample(
                    date: Self.eatenDate(of: meal, now: now),
                    calories: meal.totalCalories,
                    proteinGrams: meal.totalProtein,
                    carbsGrams: meal.totalCarbs,
                    fatGrams: meal.totalFat,
                    name: meal.mealName,
                    syncIdentifier: Self.syncPrefix + key,
                    syncVersion: version
                )
                do {
                    if try await healthKit.writeNutrition(sample) {
                        records[key] = Record(fingerprint: fingerprint, version: version, day: day)
                    }
                } catch {
                    logger.error("Health meal write failed: \(error.localizedDescription)")
                }
            }
        }

        // Meals no longer eaten (undone, deleted, un-eaten): remove from Health.
        for key in Array(records.keys) where !seen.contains(key) {
            do {
                try await healthKit.deleteNutrition(syncIdentifier: Self.syncPrefix + key)
                records[key] = nil
            } catch {
                logger.error("Health meal delete failed: \(error.localizedDescription)")
            }
        }

        saveRecords(records)
    }

    // MARK: - Helpers

    static func fingerprint(of meal: PlannedMeal) -> String {
        "\(meal.mealName)|\(Int(meal.totalCalories.rounded()))|\(Int(meal.totalProtein.rounded()))|"
            + "\(Int(meal.totalCarbs.rounded()))|\(Int(meal.totalFat.rounded()))"
    }

    /// When the meal was eaten, never in the future.
    static func eatenDate(of meal: PlannedMeal, now: Date) -> Date {
        if let eaten = meal.actualEatenAt {
            return min(eaten, now)
        }
        let calendar = Calendar.current
        let parts = meal.scheduledTime.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2,
           let scheduled = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: meal.dayDate)
        {
            return min(scheduled, now)
        }
        return min(meal.dayDate, now)
    }

    private func loadRecords() -> [String: Record] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let records = try? JSONDecoder().decode([String: Record].self, from: data)
        else {
            return [:]
        }
        return records
    }

    private func saveRecords(_ records: [String: Record]) {
        if let data = try? JSONEncoder().encode(records) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
