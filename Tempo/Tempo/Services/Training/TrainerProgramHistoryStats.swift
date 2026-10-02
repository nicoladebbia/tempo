//
// TrainerProgramHistoryStats.swift
// Tempo
//
// Fix #11(c) — completion stats for a TrainerProgram (archived history rows
// and, since the compliance fix, the active program's own card).
//
// compliance = sessions actually DONE / sessions scheduled to date.
// "Scheduled" comes from the program's own calendar (`sessions(on:)`, which
// honours dated skips), NOT from the plans Tempo happened to generate — a
// plan only exists for a day the athlete opened, so counting plans made a
// skipped week invisible and the percentage too high. "Done" is real logged
// work (`TrainerReportBuilder.didRealWork`), never a merely-saved plan.
// Days Tempo itself overrode (paused, match day, red-recovery bench) are not
// scheduled — the same exclusions as the missed-session prompt
// (`TrainerScheduleOverrides`).
// Today's session counts as scheduled only once it's done (it isn't "missed"
// until the day is over). Sequence mode has no calendar to walk, so there
// "scheduled" is the sessions Tempo carried (done, or lapsed unfinished).
//

import Foundation
import SwiftData

// MARK: - TrainerProgramHistoryStats

enum TrainerProgramHistoryStats {
    struct Stats: Equatable {
        let done: Int
        let scheduled: Int

        var fraction: Double {
            guard scheduled > 0 else {
                return 0
            }
            return min(1, Double(done) / Double(scheduled))
        }
    }

    @MainActor
    static func stats(for program: TrainerProgram, modelContext: ModelContext, today: Date = Date()) -> Stats {
        let all = (try? modelContext.fetch(FetchDescriptor<WorkoutPlan>())) ?? []
        return stats(for: program, plans: all, today: today, overrides: TrainerScheduleOverrides.fetch(modelContext: modelContext))
    }

    /// Pure core: `plans` may include other programs' rows — they're filtered out.
    static func stats(
        for program: TrainerProgram,
        plans: [WorkoutPlan],
        today: Date = Date(),
        overrides: TrainerScheduleOverrides = TrainerScheduleOverrides()
    ) -> Stats {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: today)
        let prefix = "\(program.id.uuidString)#"

        // One slot per (plan, session key): a two-a-day plan carries two.
        var slots: [(date: Date, key: String, done: Bool)] = []
        for plan in plans {
            for key in [plan.programSessionKey, plan.programSecondaryKey].compactMap(\.self) where key.hasPrefix(prefix) {
                let day = cal.startOfDay(for: plan.date)
                guard day <= startOfToday else {
                    continue
                }
                slots.append((day, key, TrainerReportBuilder.didRealWork(plan, sessionKey: key)))
            }
        }
        let doneSlots = slots.filter(\.done)

        if program.scheduleMode == .sequence {
            let scheduled = slots.filter { $0.done || $0.date < startOfToday }.count
            return Stats(done: doneSlots.count, scheduled: scheduled)
        }

        let start = cal.startOfDay(for: program.startDate)
        let end: Date = if program.isActive {
            startOfToday
        } else {
            min(startOfToday, max(program.endedAt.map { cal.startOfDay(for: $0) } ?? slots.map(\.date).max() ?? start, start))
        }
        guard start <= end else {
            return Stats(done: 0, scheduled: 0)
        }

        // The plan row stored per day, for the red-recovery check.
        var planByDay: [Date: WorkoutPlan] = [:]
        for plan in plans {
            planByDay[cal.startOfDay(for: plan.date)] = plan
        }

        var scheduled = 0
        var cursor = start
        while cursor <= end {
            let overridden = overrides.overrides(cursor, persisted: planByDay[cursor], calendar: cal)
            for session in program.sessions(on: cursor) {
                if overridden {
                    continue
                }
                if TrainerReportBuilder.isStillPending(scheduledDate: cursor, now: today) {
                    let key = program.sessionKey(weekIndex: session.weekIndex, dayIndex: session.dayIndex)
                    guard doneSlots.contains(where: { $0.key == key && $0.date == cursor }) else {
                        continue
                    }
                }
                scheduled += 1
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else {
                break
            }
            cursor = next
        }
        let done = doneSlots.filter { $0.date >= start }.count
        return Stats(done: min(done, scheduled), scheduled: scheduled)
    }
}
