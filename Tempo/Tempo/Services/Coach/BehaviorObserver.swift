//
// BehaviorObserver.swift
// Tempo
//
// Coach v2.1 Phase 4b — nightly behavior scanner.
//
// Inspects the last `windowDays` of PlannedMeal data and:
//   1) Proposes new observed preferences when a pattern is strong enough.
//   2) Reinforces existing preferences whose evidence still matches.
//   3) Flags contradictions (sets `needsReview: true`) when behavior
//      diverges from a high-confidence preference.
//   4) Applies one day of decay to every active preference.
//
// Pure logic — no AI calls. Wired into DailyResetCoordinator in Phase 6
// (or by an explicit observer-run in the meantime).
//
// Per .plans/coach-v2.1/02-data-model.md and §03-services-and-data-flow.md
// (Nightly jobs).
//

import Foundation
import SwiftData

// MARK: - BehaviorObserver

enum BehaviorObserver {
    /// Minimum number of matching days in the window before a pattern
    /// proposes a new preference. 4-of-7 keeps occasional events out of
    /// the memory layer.
    static let minOccurrencesToPropose = 4

    /// Initial confidence for an observed-from-behavior preference.
    static let proposedConfidence = 0.5

    /// Window in days for "actual eat time" timing variance ≥ 30min off
    /// schedule. Below this threshold, no preference is proposed.
    static let timingVarianceMinutes: Double = 30

    /// Result of one observer run. Useful for the daily-reset log + tests.
    struct RunReport: Equatable {
        var proposed: Int = 0
        var reinforced: Int = 0
        var contradictionsFlagged: Int = 0
        var decayed: Int = 0
        var deactivatedByDecay: Int = 0
    }

    // MARK: - Entry

    /// Run all scans for the supplied date. `today` defaults to now.
    /// `windowDays` defaults to 7. Throws on persistence failure.
    @MainActor
    @discardableResult
    static func observe(
        modelContext context: ModelContext,
        today: Date = Date(),
        windowDays: Int = 7,
        calendar: Calendar = .current
    ) throws -> RunReport {
        var report = RunReport()

        let mealsInWindow = fetchPlannedMeals(in: context, today: today, windowDays: windowDays, calendar: calendar)

        // Sub-scan 1 — recurring meal skips.
        scanMealSkipPatterns(
            meals: mealsInWindow,
            today: today,
            context: context,
            report: &report
        )

        // Sub-scan 2 — meal timing variance ("you eat lunch ~25min after schedule").
        scanMealTimingVariance(
            meals: mealsInWindow,
            today: today,
            context: context,
            report: &report
        )

        // Sub-scan 3 — daily decay across all active preferences.
        applyDecayToAllActive(in: context, report: &report)

        try context.save()
        return report
    }

    // MARK: - Fetch helpers

    @MainActor
    private static func fetchPlannedMeals(
        in context: ModelContext,
        today: Date,
        windowDays: Int,
        calendar: Calendar
    ) -> [PlannedMeal] {
        let dayStart = calendar.startOfDay(for: today)
        guard let windowStart = calendar.date(
            byAdding: .day,
            value: -windowDays,
            to: dayStart
        ) else {
            return []
        }
        let descriptor = FetchDescriptor<PlannedMeal>(
            predicate: #Predicate<PlannedMeal> { meal in
                meal.dayDate >= windowStart && meal.dayDate < dayStart
            }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Sub-scan 1 — meal skips

    /// Looks for a meal slot (Breakfast/Lunch/Dinner/Snack) skipped on
    /// ≥4 of the last 7 days. Proposes a `meal_timing.{slot}.skipped`
    /// preference OR reinforces it. When the pattern is absent on a
    /// previously-high-confidence skip pref, flags it for review.
    @MainActor
    static func scanMealSkipPatterns(
        meals: [PlannedMeal],
        today: Date,
        context: ModelContext,
        report: inout RunReport
    ) {
        // Group meals by mealNumber, count skipped vs total in window.
        var totals: [Int: Int] = [:]
        var skips: [Int: Int] = [:]
        for meal in meals {
            totals[meal.mealNumber, default: 0] += 1
            if meal.status == .skipped {
                skips[meal.mealNumber, default: 0] += 1
            }
        }

        for (mealNumber, skipCount) in skips {
            let slot = mealSlotName(for: mealNumber)
            let subject = "meal_timing.\(slot).skipped"
            let existing = fetchActivePreference(subject: subject, in: context)

            if skipCount >= minOccurrencesToPropose {
                if let existing {
                    existing.markReinforced(at: today)
                    report.reinforced += 1
                } else {
                    let pref = LearnedPreference(
                        text: "user usually skips \(slot)",
                        subject: subject,
                        source: .observed,
                        scope: .always,
                        confidence: proposedConfidence,
                        lastSeenAt: today
                    )
                    context.insert(pref)
                    report.proposed += 1
                }
            } else if let existing, existing.confidence >= 0.7 {
                // Behavior no longer supports the high-confidence preference —
                // flag for review. Don't auto-mutate; agent surfaces in next chat.
                if !existing.needsReview {
                    existing.needsReview = true
                    report.contradictionsFlagged += 1
                }
            }

            _ = totals[mealNumber] // surface for future "skip-ratio" logic; unused for now
        }
    }

    // MARK: - Sub-scan 2 — meal timing variance

    /// Looks for meals where `actualEatenAt` is consistently ≥30min off
    /// the scheduled time across the window. Proposes a
    /// `meal_timing.{slot}.actual` preference describing the user's real
    /// rhythm. Caller (assembler) uses this to bias next plan's anchors.
    @MainActor
    static func scanMealTimingVariance(
        meals: [PlannedMeal],
        today: Date,
        context: ModelContext,
        report: inout RunReport
    ) {
        // Group meals with actualEatenAt by mealNumber, compute mean
        // signed offset (positive = late).
        var offsetsByNumber: [Int: [Double]] = [:]
        for meal in meals {
            guard let eaten = meal.actualEatenAt else { continue }
            guard let scheduled = scheduledDate(for: meal) else { continue }
            let offsetMin = eaten.timeIntervalSince(scheduled) / 60.0
            offsetsByNumber[meal.mealNumber, default: []].append(offsetMin)
        }

        for (mealNumber, offsets) in offsetsByNumber where offsets.count >= 2 {
            let mean = offsets.reduce(0, +) / Double(offsets.count)
            guard abs(mean) >= timingVarianceMinutes else { continue }
            let slot = mealSlotName(for: mealNumber)
            let subject = "meal_timing.\(slot).actual"
            let direction = mean > 0 ? "after" : "before"
            let minutes = Int(abs(mean).rounded())
            let text = "user usually eats \(slot) ~\(minutes) min \(direction) schedule"

            let existing = fetchActivePreference(subject: subject, in: context)
            if let existing {
                existing.markReinforced(at: today)
                existing.text = text // refresh wording with latest minutes
                report.reinforced += 1
            } else {
                let pref = LearnedPreference(
                    text: text,
                    subject: subject,
                    source: .observed,
                    scope: .always,
                    confidence: proposedConfidence,
                    lastSeenAt: today
                )
                context.insert(pref)
                report.proposed += 1
            }
        }
    }

    // MARK: - Sub-scan 3 — daily decay

    /// Applies one day of decay to every active preference. Counts
    /// decayed vs auto-deactivated for the report. Run last so newly
    /// proposed/reinforced rows from this run don't get decayed.
    @MainActor
    static func applyDecayToAllActive(
        in context: ModelContext,
        report: inout RunReport
    ) {
        let descriptor = FetchDescriptor<LearnedPreference>(
            predicate: #Predicate<LearnedPreference> { $0.isActive }
        )
        let prefs = (try? context.fetch(descriptor)) ?? []
        for pref in prefs {
            let wasActive = pref.isActive
            pref.applyDailyDecay()
            if wasActive && !pref.isActive {
                report.deactivatedByDecay += 1
            }
            report.decayed += 1
        }
    }

    // MARK: - Helpers

    @MainActor
    private static func fetchActivePreference(
        subject: String,
        in context: ModelContext
    ) -> LearnedPreference? {
        let descriptor = FetchDescriptor<LearnedPreference>(
            predicate: #Predicate<LearnedPreference> { pref in
                pref.isActive && pref.subject == subject
            }
        )
        return (try? context.fetch(descriptor))?.first
    }

    static func mealSlotName(for mealNumber: Int) -> String {
        switch mealNumber {
        case 1: return "breakfast"
        case 2: return "lunch"
        case 3: return "dinner"
        case 4: return "snack"
        default: return "meal_\(mealNumber)"
        }
    }

    /// Combine `PlannedMeal.dayDate` + `scheduledTime` (HH:mm) into a Date.
    /// Returns nil on malformed scheduled time.
    static func scheduledDate(
        for meal: PlannedMeal,
        calendar: Calendar = .current
    ) -> Date? {
        let parts = meal.scheduledTime.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1])
        else { return nil }
        let dayStart = calendar.startOfDay(for: meal.dayDate)
        return calendar.date(bySettingHour: h, minute: m, second: 0, of: dayStart)
    }
}
