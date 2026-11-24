//
// BodyCompositionRefresh.swift
// Tempo
//
// Opening Body progress reads Health's newest weight, body fat and lean mass and
// keeps them as today's snapshot, so a weigh-in made after the day's first
// refresh shows up at once. The same one-row-per-day record the Dashboard keeps.
//

import Foundation
import SwiftData

enum BodyCompositionRefresh {
    /// Keeps `data` as the snapshot for `day`. Nothing is written when Health
    /// has no body data at all, so an empty read never blanks a stored day.
    /// Returns whether a row was written.
    @MainActor
    @discardableResult
    static func store(
        _ data: BodyCompositionData, on day: Date = Date(), in context: ModelContext,
        calendar: Calendar = .current
    ) -> Bool {
        guard data.weightKg != nil || data.bodyFatPercent != nil || data.leanMassKg != nil else {
            return false
        }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return false
        }
        let existing = try? context.fetch(FetchDescriptor<BodyComposition>(
            predicate: #Predicate<BodyComposition> { $0.date >= start && $0.date < end }
        )).first
        if let existing {
            existing.weightKg = data.weightKg
            existing.bodyFatPercent = data.bodyFatPercent
            existing.leanMassKg = data.leanMassKg
            existing.measurementDate = data.measurementDate
            existing.capturedAt = Date()
        } else {
            context.insert(BodyComposition(
                date: start,
                weightKg: data.weightKg,
                bodyFatPercent: data.bodyFatPercent,
                leanMassKg: data.leanMassKg,
                measurementDate: data.measurementDate
            ))
        }
        return (try? context.save()) != nil
    }

    /// Reads Health and keeps the result. Health being unavailable or empty is
    /// not an error here: the page shows what is already stored.
    @MainActor
    static func refresh(from healthKit: any HealthKitServiceProtocol, in context: ModelContext) async {
        guard let data = try? await healthKit.fetchBodyComposition() else {
            return
        }
        store(data, in: context)
    }
}
