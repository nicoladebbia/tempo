//
// VenuePatternLearner.swift
// Tempo
//
// Builds VenueSamples from the three evidence sources and recomputes the
// per-weekday VenuePattern rows (docs/INTELLIGENT_TRAINING_SYSTEM.md §16.2:
// "pure recompute function over the last ~8 weeks of confirmed sessions, run
// on session save — cheap"). Rows are derived data: always rebuilt whole,
// never incrementally mutated, so a bug here can't corrupt anything that
// matters — re-running heals it.
//
// Evidence priority per day: an explicit VenueConfirmation overrides the
// venue inferred from the WorkoutType of that day's completed plan; a
// confirmation on a day with no completed plan still contributes venue/time
// evidence on its own (the user told us the habit — believe it).
//

import Foundation
import SwiftData

enum VenuePatternLearner {
    /// §16.2 — the trailing learning window.
    static let windowWeeks = 8

    // MARK: - Pure sample building

    /// Maps raw rows to learner samples. Pure given its inputs; the SwiftData
    /// fetches live in `recompute` so this stays unit-testable.
    static func buildSamples(
        plans: [WorkoutPlan],
        activities: [ActivitySession],
        confirmations: [VenueConfirmation],
        calendar: Calendar = .current
    ) -> [VenueSample] {
        let confirmationByDay = Dictionary(
            confirmations.map { (calendar.startOfDay(for: $0.dayKey), $0) },
            uniquingKeysWith: { _, newest in newest }
        )

        var samples: [VenueSample] = []
        var daysWithCompletedPlan: Set<Date> = []

        for plan in plans {
            let day = calendar.startOfDay(for: plan.date)
            let confirmation = confirmationByDay[day]
            switch plan.status {
            case .completed:
                daysWithCompletedPlan.insert(day)
                samples.append(VenueSample(
                    date: plan.startedAt ?? plan.date,
                    startMin: plan.startedAt.map { minutesAfterMidnight($0, calendar: calendar) }
                        ?? confirmation?.startMin,
                    durationMin: plan.actualDurationMinutes ?? plan.durationMinutes,
                    venue: confirmation?.venue ?? plan.type.inferredVenue,
                    completed: true,
                    prescribed: true
                ))
            case .skipped:
                // §15.2 — only a USER skip counts against the completion rate.
                // floorForced ("plan didn't fit today's body") and
                // venueUnavailable are not user failures; they don't enter the
                // denominator at all.
                let userFlake = plan.skipReason == nil || plan.skipReason == .userSkipped
                if userFlake {
                    samples.append(VenueSample(
                        date: plan.date, startMin: nil, durationMin: nil,
                        venue: nil, completed: false, prescribed: true
                    ))
                }
            case .planned, .inProgress:
                // Unresolved days are not evidence (today's pending plan must
                // not read as a skip).
                break
            }
        }

        // Whoop-detected / manual sessions NOT linked to a plan: real training
        // that was never prescribed. Venue/time evidence yes; completion-rate
        // denominator no.
        for activity in activities where activity.workoutPlanID == nil {
            samples.append(VenueSample(
                date: activity.startTime,
                startMin: minutesAfterMidnight(activity.startTime, calendar: calendar),
                durationMin: activity.durationMinutes.map { Int($0) },
                venue: WorkoutType(rawValue: activity.workoutType)?.inferredVenue,
                completed: true,
                prescribed: false
            ))
        }

        // Confirmations on days that produced no completed plan: standalone
        // venue/time evidence. (On completed-plan days the confirmation already
        // overrode that sample's venue — adding it again would double-count.)
        for (day, confirmation) in confirmationByDay where !daysWithCompletedPlan.contains(day) {
            samples.append(VenueSample(
                date: day,
                startMin: confirmation.startMin,
                durationMin: nil,
                venue: confirmation.venue,
                completed: true,
                prescribed: false
            ))
        }

        return samples
    }

    static func minutesAfterMidnight(_ date: Date, calendar: Calendar = .current) -> Int {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    // MARK: - Recompute (the on-save hook)

    /// Rebuilds all 7 weekday rows from the trailing window. Called after a
    /// session completion is persisted and after a venue confirmation. Cheap:
    /// three small fetches + pure math; no AI, no network.
    @MainActor
    static func recompute(modelContext: ModelContext, now: Date = Date()) {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .weekOfYear, value: -windowWeeks, to: now) else { return }

        let plans = (try? modelContext.fetch(FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { $0.date >= cutoff }
        ))) ?? []
        let activities = (try? modelContext.fetch(FetchDescriptor<ActivitySession>(
            predicate: #Predicate { $0.date >= cutoff }
        ))) ?? []
        let confirmations = (try? modelContext.fetch(FetchDescriptor<VenueConfirmation>(
            predicate: #Predicate { $0.dayKey >= cutoff }
        ))) ?? []

        let samples = buildSamples(
            plans: plans, activities: activities,
            confirmations: confirmations, calendar: calendar
        )

        let existing = (try? modelContext.fetch(FetchDescriptor<VenuePattern>())) ?? []
        let rowByWeekday = Dictionary(existing.map { ($0.weekday, $0) }, uniquingKeysWith: { a, _ in a })

        for weekday in 1 ... 7 {
            let snapshot = VenuePatternMath.snapshot(samples: samples, weekday: weekday, calendar: calendar)
            if let snapshot {
                let row = rowByWeekday[weekday] ?? {
                    let fresh = VenuePattern(weekday: weekday)
                    modelContext.insert(fresh)
                    return fresh
                }()
                row.venueRaw = snapshot.venue?.rawValue
                row.medianStartMin = snapshot.medianStartMin
                row.medianDurationMin = snapshot.medianDurationMin
                row.completionRate = snapshot.completionRate
                row.sampleCount = snapshot.sampleCount
                row.updatedAt = now
            } else if let stale = rowByWeekday[weekday] {
                // Below the cold-start gate (e.g. old samples aged out of the
                // window) — a stale row must not keep proposing.
                modelContext.delete(stale)
            }
        }

        try? modelContext.save()
        #if DEBUG
            print("\(DebugTrace.prefix)[venue] recompute: \(samples.count) samples → \(existing.count) rows refreshed")
        #endif
    }
}
