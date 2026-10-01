//
// WaterStore.swift
// Tempo
//
// Saves water taps on the phone (SwiftData `WaterIntakeLog`) and mirrors them
// to Apple Health as dietaryWater. Undo removes the row AND the Health sample.
// Posts `.tempoWaterLogged` after every change so Nutrition Today and the
// Dashboard Fuel tile re-read the total. Tempo never reads other apps' water.
//

import Foundation
import OSLog
import SwiftData

extension Notification.Name {
    /// Posted (main thread) after water was added, removed or undone.
    static let tempoWaterLogged = Notification.Name("tempo.water.logged")
}

@MainActor
final class WaterStore {
    /// Largest single entry accepted (a typo guard, not a medical limit).
    static let maxEntryMl = 3000

    private let context: ModelContext
    private let healthKit: (any HealthKitServiceProtocol)?
    private let logger = Logger(subsystem: "app.tempo.Tempo", category: "water")

    init(context: ModelContext, healthKit: (any HealthKitServiceProtocol)?) {
        self.context = context
        self.healthKit = healthKit
    }

    // MARK: - Reads

    /// Total ml saved for `day`'s calendar date.
    static func total(on day: Date = Date(), in context: ModelContext) -> Int {
        entries(on: day, in: context).reduce(0) { $0 + $1.ml }
    }

    func total(on day: Date = Date()) -> Int {
        Self.total(on: day, in: context)
    }

    /// Entries for the day, oldest first.
    static func entries(on day: Date, in context: ModelContext) -> [WaterIntakeLog] {
        let start = Calendar.current.startOfDay(for: day)
        let descriptor = FetchDescriptor<WaterIntakeLog>(
            predicate: #Predicate<WaterIntakeLog> { $0.day == start },
            sortBy: [SortDescriptor(\.loggedAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Writes

    /// Saves `ml` (1...maxEntryMl) and writes it to Health. Returns the new
    /// row, or nil when the amount is out of range or the save failed.
    @discardableResult
    func add(ml: Int, at date: Date = Date()) -> WaterIntakeLog? {
        guard ml > 0, ml <= Self.maxEntryMl else {
            return nil
        }
        let log = WaterIntakeLog(ml: ml, loggedAt: date)
        context.insert(log)
        do {
            try context.save()
        } catch {
            context.delete(log)
            logger.error("water add failed: \(error.localizedDescription)")
            return nil
        }
        if let healthKit {
            let id = log.healthSyncID
            let amount = Double(ml)
            Task {
                do {
                    try await healthKit.writeWater(ml: amount, date: date, syncIdentifier: id)
                } catch {
                    Logger(subsystem: "app.tempo.Tempo", category: "water")
                        .error("Health water write failed: \(error.localizedDescription)")
                }
            }
        }
        NotificationCenter.default.post(name: .tempoWaterLogged, object: nil)
        return log
    }

    /// Removes the most recent entry of `day` (default today). Returns the ml
    /// removed, nil when there was nothing to undo.
    @discardableResult
    func undoLast(on day: Date = Date()) -> Int? {
        guard let last = Self.entries(on: day, in: context).last else {
            return nil
        }
        return remove(last) ? last.ml : nil
    }

    @discardableResult
    func remove(id: UUID) -> Bool {
        let descriptor = FetchDescriptor<WaterIntakeLog>(predicate: #Predicate<WaterIntakeLog> { $0.id == id })
        guard let log = (try? context.fetch(descriptor))?.first else {
            return false
        }
        return remove(log)
    }

    private func remove(_ log: WaterIntakeLog) -> Bool {
        let syncID = log.healthSyncID
        context.delete(log)
        do {
            try context.save()
        } catch {
            context.rollback()
            logger.error("water remove failed: \(error.localizedDescription)")
            return false
        }
        if let healthKit {
            Task {
                do {
                    try await healthKit.deleteNutrition(syncIdentifier: syncID)
                } catch {
                    Logger(subsystem: "app.tempo.Tempo", category: "water")
                        .error("Health water delete failed: \(error.localizedDescription)")
                }
            }
        }
        NotificationCenter.default.post(name: .tempoWaterLogged, object: nil)
        return true
    }
}
