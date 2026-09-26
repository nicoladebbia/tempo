//
// TrainingViewModel+TrainerProgram.swift
// Tempo
//
// Following the athlete's own trainer. While a TrainerProgram is active:
// - its sessions replace the generated gym days (type + exercises from the
//   trainer), other gym/conditioning days become rest — "your trainer's plan
//   plus your football";
// - Tempo still adjusts automatically: a red-recovery day stays mobility, a
//   match day stays football, the recovery multiplier and pain notes scale
//   the loads, and the daily coach/safety floor run as on any day.
// Tempo's scheduled deload is skipped on trainer days — the trainer owns the
// periodization.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    /// The one active trainer program, if any. Fix #11(b) — first promotes a
    /// due queued program (see `promoteQueuedProgramIfDue`): cheap and
    /// idempotent, so running it on every read (the same "regenerate
    /// everything, every time" pattern this whole file already uses) needs
    /// no separate app-launch hook.
    func activeTrainerProgram(modelContext: ModelContext) -> TrainerProgram? {
        promoteQueuedProgramIfDue(modelContext: modelContext)
        let descriptor = FetchDescriptor<TrainerProgram>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Weekly-upload feature — the active program, if it's `.weekly` cadence
    /// AND due (or overdue) for its next upload (`TrainerProgramWeeklyUpload
    /// .shouldPromptUpload`). Drives `WeeklyUploadPromptCard` and the
    /// Sunday/Monday reminders (`WeeklyUploadReminderScheduler`).
    func weeklyUploadDue(modelContext: ModelContext, now: Date = Date()) -> TrainerProgram? {
        guard let program = activeTrainerProgram(modelContext: modelContext) else {
            return nil
        }
        let all = (try? modelContext.fetch(FetchDescriptor<TrainerProgram>())) ?? []
        guard TrainerProgramWeeklyUpload.shouldPromptUpload(programs: all, activeProgram: program, now: now) else {
            return nil
        }
        return program
    }

    /// Fix #11(b) — a program queued as "starts after the current one ends"
    /// (or on a chosen date) is saved with `isActive == false` and
    /// `queuedActivationDate` set (`TrainerProgramSaver.save`). Once that
    /// date arrives, it becomes active and the program it replaces is
    /// archived (simply left `isActive == false` — already how every past
    /// program is represented, see `TrainerProgramView`'s "past programs"
    /// list and `TrainerProgramHistoryStats`).
    private func promoteQueuedProgramIfDue(modelContext: ModelContext) {
        let today = Calendar.current.startOfDay(for: Date())
        let all = (try? modelContext.fetch(FetchDescriptor<TrainerProgram>())) ?? []
        let due = all.filter { !$0.isActive && ($0.queuedActivationDate.map { $0 <= today } ?? false) }
        guard !due.isEmpty else {
            return
        }
        // `TrainerProgramSaver.save` only ever leaves ONE program queued at a
        // time (a new queue cancels any other), but pick deterministically
        // anyway (earliest activation date, then oldest) — a non-deterministic
        // `first(where:)` here would thrash: promote due[0] on this read,
        // then on the NEXT read due[1] (untouched, still queued) would ALSO
        // match `!isActive`, get promoted, and demote due[0] right back to
        // inactive, flip-flopping the active program across reads forever.
        let winner = due.min {
            ($0.queuedActivationDate ?? .distantFuture, $0.createdAt) < ($1.queuedActivationDate ?? .distantFuture, $1.createdAt)
        }
        guard let winner else {
            return
        }
        for other in all where other.isActive {
            other.isActive = false
        }
        // Every other due-but-not-chosen queued program is cleared too (not
        // left to be silently promoted — and immediately un-promoted — on a
        // later read): it stays saved, just no longer self-activating.
        for other in due where other.id != winner.id {
            other.queuedActivationDate = nil
        }
        winner.isActive = true
        winner.queuedActivationDate = nil
        try? modelContext.save()
        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
    }

    /// Overlay the active program on generated plans (mutates them in place).
    /// Pure apart from the plans themselves — unit-tested.
    ///
    /// Fix #6 — `completedSequenceCount`/`priorDayWasLift` are the caller's
    /// snapshot of real progress AS OF the first day in `plans` (see
    /// `TrainingViewModel.completedTrainerSessionCount`/
    /// `trainerProgramPriorDayWasLift`); inside the loop they're advanced
    /// locally so the rest of a multi-day batch (e.g. a full week) previews
    /// what happens if the athlete stays on pace, without mutating anything
    /// outside this call.
    nonisolated static func applyTrainerProgram(
        _ program: TrainerProgram,
        to plans: [WorkoutPlan],
        matchDayKeys: Set<Date>,
        completedSequenceCount: Int = 0,
        priorDayWasLift: Bool = false
    ) {
        let cal = Calendar.current
        var sequenceCursor = completedSequenceCount
        var previousDayWasLift = priorDayWasLift
        for plan in plans {
            let day = cal.startOfDay(for: plan.date)
            // A dated match is a fixed commitment — the match day stays.
            if matchDayKeys.contains(day) {
                // A match day is never a lift — clears the consecutive-lift
                // guard for tomorrow (it doesn't consume a sequence step).
                previousDayWasLift = false
                continue
            }
            // Red recovery: the engine already moved the day to mobility with
            // a zero multiplier — Tempo adjusts automatically, so keep it.
            let isRedRecoveryDay = plan.type == .mobility && plan.recoveryAdjustment == 0
            let resolution = resolveSession(
                program: program,
                on: plan.date,
                sequenceCursor: sequenceCursor,
                previousDayWasLift: previousDayWasLift
            )
            plan.programSecondaryKey = nil
            if let main = resolution.main {
                if isRedRecoveryDay {
                    plan.notes = "Recovery is low — your trainer's \(main.day.title ?? "session") is paused today."
                    plan.programSessionKey = nil
                    // A paused session never actually ran — sequence mode
                    // must not advance past it (it stays next-due), and it
                    // doesn't count as "yesterday was a lift" either.
                    previousDayWasLift = false
                    continue
                }
                plan.type = main.day.workoutType
                plan.programSessionKey = program.sessionKey(weekIndex: main.weekIndex, dayIndex: main.dayIndex)
                plan.notes = main.day.title ?? "Trainer session"
                // A second session the same day becomes the day's second part
                // (two-a-day): lift then shuttles, or two conditioning blocks.
                // Prefer a conditioning session after a lift.
                let others = resolution.sessions.filter { $0.dayIndex != main.dayIndex }
                if let second = others.first(where: { !$0.day.isStrength }) ?? others.first {
                    plan.secondarySessionType = second.day.workoutType
                    plan.programSecondaryKey = program.sessionKey(weekIndex: second.weekIndex, dayIndex: second.dayIndex)
                } else {
                    plan.secondarySessionType = nil
                }
                if program.scheduleMode == .sequence {
                    sequenceCursor += 1
                }
                previousDayWasLift = main.day.isStrength
            } else if !isRedRecoveryDay {
                plan.programSessionKey = nil
                switch plan.type {
                case .football,
                     .mobility,
                     .rest:
                    break // your sport / recovery stay as planned
                default:
                    plan.type = .rest
                    plan.notes = "Rest — not on your trainer's program."
                }
                plan.secondarySessionType = nil
                previousDayWasLift = false
            } else {
                // No session resolved AND it's a red-recovery day (fixed mode
                // with nothing that weekday, or sequence mode whose
                // cadence/consecutive-lift guard also came up empty). Not a
                // lift either way — without this, a stale `true` from a
                // day or two back could wrongly defer a LATER, unrelated
                // step under the consecutive-lift guard.
                previousDayWasLift = false
            }
        }
    }

    /// One day's session(s), branched on the program's schedule mode.
    ///
    /// `.fixed` — unchanged weekday lookup (`sessions(on:)`/`session(on:)`).
    ///
    /// `.sequence` — cadence (WHICH calendar days can carry a session at
    /// all) still comes from the program's own authored weekday pattern for
    /// the calendar week `date` falls in (the same number of session-days,
    /// same rest-day spacing the trainer wrote) — sequence mode changes
    /// WHICH session lands on a training day, not HOW MANY training days
    /// there are. Content is whatever `sequenceSession(completedCount:)`
    /// says is next-due.
    ///
    /// Guard (explicitly required by fix #6): sequence mode must never
    /// schedule two STRENGTH sessions on consecutive calendar days. Because
    /// a missed session carries forward, an athlete who falls behind could
    /// otherwise catch up into exactly that — e.g. a missed Monday lift
    /// lands on Tuesday right after Tuesday's own scheduled lift. When the
    /// next-due step is a lift AND yesterday already ran one
    /// (`previousDayWasLift`), that step is deferred — today falls through
    /// to the "not on the program" branch (rest, or an untouched football/
    /// match/mobility day) and the step stays next-due for the following
    /// training day. It is NOT consumed (`sequenceCursor` only advances when
    /// a session actually resolves onto a real day), so nothing is skipped —
    /// it simply waits one more day, exactly like a missed day already does.
    private nonisolated static func resolveSession(
        program: TrainerProgram,
        on date: Date,
        sequenceCursor: Int,
        previousDayWasLift: Bool
    ) -> (main: (weekIndex: Int, dayIndex: Int, day: ProgramDay)?, sessions: [(weekIndex: Int, dayIndex: Int, day: ProgramDay)]) {
        switch program.scheduleMode {
        case .fixed:
            return (program.session(on: date), program.sessions(on: date))
        case .sequence:
            guard let weekIndex = program.weekIndex(on: date) else {
                return (nil, [])
            }
            let weekday = TrainerProgram.isoWeekday(of: date)
            let cadenceWeekdays = Set(program.weeks[weekIndex].days.filter { !$0.exercises.isEmpty }.map(\.weekday))
            guard cadenceWeekdays.contains(weekday),
                  let step = program.sequenceSession(completedCount: sequenceCursor)
            else {
                return (nil, [])
            }
            if step.day.isStrength, previousDayWasLift {
                return (nil, [])
            }
            var sessions: [(weekIndex: Int, dayIndex: Int, day: ProgramDay)] = [(step.weekIndex, step.dayIndex, step.day)]
            if let secondaryIndex = step.secondaryDayIndex {
                sessions.append((step.weekIndex, secondaryIndex, program.weeks[step.weekIndex].days[secondaryIndex]))
            }
            return (sessions[0], sessions)
        }
    }

    /// Fix #6 — how many of `program`'s sessions have actually been marked
    /// complete, across all time (not deduped by session key — see
    /// `TrainerProgram.sequenceSession`). Only the MAIN session's `status`
    /// counts a step as done; a paired secondary's own `secondaryCompleted`
    /// flag isn't tracked separately here, matching `session(on:)`/
    /// `applyTrainerProgram` already treating the main session as the day's
    /// representative.
    func completedTrainerSessionCount(for program: TrainerProgram, modelContext: ModelContext) -> Int {
        let prefix = "\(program.id.uuidString)#"
        let descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate<WorkoutPlan> { $0.statusRaw == "completed" }
        )
        let completed = (try? modelContext.fetch(descriptor)) ?? []
        return completed.filter { ($0.programSessionKey?.hasPrefix(prefix)) ?? false }.count
    }

    /// Fix #6 (consecutive-lift guard) — whether the persisted plan for the
    /// calendar day before `monday` (i.e. the previous Sunday) was a
    /// strength session from `program`. Used to seed `applyTrainerProgram`'s
    /// `priorDayWasLift` at a week boundary, where the day before the batch
    /// isn't itself part of the batch.
    func trainerProgramPriorDayWasLift(before monday: Date, program: TrainerProgram, modelContext: ModelContext) -> Bool {
        guard let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: monday) else {
            return false
        }
        let start = Calendar.current.startOfDay(for: dayBefore)
        let descriptor = FetchDescriptor<WorkoutPlan>(predicate: #Predicate<WorkoutPlan> { $0.date == start })
        guard let plan = (try? modelContext.fetch(descriptor))?.first else {
            return false
        }
        let prefix = "\(program.id.uuidString)#"
        return plan.type.isGymWorkout && (plan.programSessionKey?.hasPrefix(prefix) ?? false)
    }

    // MARK: - Fix #6 — missed fixed-mode session swap

    /// A past, fixed-mode session the athlete didn't do, offered on Today as
    /// "Missed <session> — do it today?".
    struct MissedTrainerSession {
        let date: Date
        let sessionKey: String
        let day: ProgramDay
    }

    /// Fixed mode only (sequence mode never has a "missed" session — it just
    /// carries forward automatically, see `sequenceSession`). Looks back up
    /// to a week for the MOST RECENT day the program assigned a session to
    /// that wasn't completed and wasn't legitimately overridden (a dated
    /// match, or a red-recovery pause both already stand as Tempo's own
    /// deliberate call, not a miss). nil when there's no active fixed-mode
    /// program, or nothing was missed in the window.
    func missedFixedSession(asOf today: Date = Date(), modelContext: ModelContext) -> MissedTrainerSession? {
        guard let program = activeTrainerProgram(modelContext: modelContext), program.scheduleMode == .fixed else {
            return nil
        }
        let cal = Calendar.current
        let matchDays = Set(fetchUpcomingMatches(modelContext: modelContext).map { cal.startOfDay(for: $0.kickoff) })
        let todayStart = cal.startOfDay(for: today)
        for offset in 1 ... 7 {
            guard let date = cal.date(byAdding: .day, value: -offset, to: todayStart) else {
                continue
            }
            guard date >= program.startDate, let session = program.session(on: date) else {
                continue
            }
            if matchDays.contains(date) {
                continue // Tempo's own deliberate override, not a miss.
            }
            let key = program.sessionKey(weekIndex: session.weekIndex, dayIndex: session.dayIndex)
            let descriptor = FetchDescriptor<WorkoutPlan>(predicate: #Predicate<WorkoutPlan> { $0.date == date })
            let persisted = (try? modelContext.fetch(descriptor))?.first
            if let persisted {
                if persisted.status == .completed {
                    continue // done
                }
                if persisted.recoveryAdjustment == 0, persisted.type == .mobility, persisted.programSessionKey == nil {
                    continue // red-recovery paused it — Tempo's own call.
                }
            }
            return MissedTrainerSession(date: date, sessionKey: key, day: session.day)
        }
        return nil
    }

    /// Swaps a missed fixed-mode session into TODAY, replacing whatever
    /// Today currently holds (only while still `.planned` — never disturbs a
    /// started/completed session). Fix #6's "do it today?" action.
    func swapInMissedSession(_ missed: MissedTrainerSession, modelContext: ModelContext) {
        guard let program = activeTrainerProgram(modelContext: modelContext) else {
            return
        }
        let today = ensureTodayPlanPersisted(modelContext: modelContext).plan
        guard today.status == .planned else {
            return
        }
        for exercise in today.orderedExercises {
            modelContext.delete(exercise)
        }
        today.exercises = []
        today.programSessionKey = missed.sessionKey
        today.programSecondaryKey = nil
        today.type = missed.day.workoutType
        today.secondarySessionType = nil
        today.notes = "Missed \(missed.day.title ?? "session") — moved to today."
        _ = populateFromTrainerProgram(today, modelContext: modelContext)
        guard modelContext.saveOrAlert("trainer program missed-session swap") else {
            return
        }
        _ = program // keeps the active-program guard above meaningful even
        // though only `today`/`missed` are mutated — swapping in a missed
        // session with no active program left would be a stale action.
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
    }

    // MARK: - Fix #11(a) — edit re-apply

    /// After editing a saved, ACTIVE program in place (`TrainerProgramSaver
    /// .update`), Today's already-persisted (and still `.planned`) row must
    /// not keep showing the pre-edit sets/reps/exercises — the ordinary
    /// `.tempoTrainingSettingsChanged` regeneration path only replaces a
    /// `.planned` row when its TYPE or `programSessionKey` changed
    /// (`TrainingViewModel+PlanResolution.ensureTodayPlanPersisted`), which
    /// an in-place edit usually doesn't touch. This forces the re-populate
    /// directly, so an edited program never orphans what Today shows.
    func reapplyEditedProgramToday(program: TrainerProgram, modelContext: ModelContext) {
        guard program.isActive else {
            return
        }
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<WorkoutPlan>(predicate: #Predicate<WorkoutPlan> { $0.date == today })
        guard let plans = try? modelContext.fetch(descriptor) else {
            return
        }
        let prefix = "\(program.id.uuidString)#"
        var changed = false
        for plan in plans where plan.status == .planned {
            let keys = [plan.programSessionKey, plan.programSecondaryKey].compactMap(\.self)
            guard keys.contains(where: { $0.hasPrefix(prefix) }) else {
                continue
            }
            for exercise in plan.orderedExercises {
                modelContext.delete(exercise)
            }
            plan.exercises = []
            if plan.programSessionKey != nil {
                _ = populateFromTrainerProgram(plan, modelContext: modelContext)
            }
            changed = true
        }
        guard changed else {
            return
        }
        _ = modelContext.saveOrAlert("trainer program edit re-apply")
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
    }

    /// The trainer's session behind a plan's key (main or second part), for
    /// display — e.g. a conditioning session's blocks on Today.
    func trainerDay(forKey key: String?, modelContext: ModelContext) -> ProgramDay? {
        guard let key,
              let programID = key.split(separator: "#").first.flatMap({ UUID(uuidString: String($0)) })
        else {
            return nil
        }
        let descriptor = FetchDescriptor<TrainerProgram>(predicate: #Predicate { $0.id == programID })
        return (try? modelContext.fetch(descriptor).first)?.day(forSessionKey: key)
    }

    /// Build a trainer-program day's exercises. Returns false when the session
    /// can't be resolved (program deleted/edited) so the caller falls back to
    /// the generated workout.
    func populateFromTrainerProgram(_ plan: WorkoutPlan, modelContext: ModelContext) -> Bool {
        guard let key = plan.programSessionKey,
              let programID = key.split(separator: "#").first.flatMap({ UUID(uuidString: String($0)) })
        else {
            return false
        }
        let descriptor = FetchDescriptor<TrainerProgram>(predicate: #Predicate { $0.id == programID })
        guard let program = try? modelContext.fetch(descriptor).first,
              let day = program.day(forSessionKey: key),
              !day.exercises.isEmpty
        else {
            return false
        }

        let library = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        var byID = Dictionary(library.map { ($0.id, $0) }) { first, _ in first }
        var byName = Dictionary(library.map { (Self.normalizedName($0.name), $0) }) { first, _ in first }
        // §13 — the trainer never writes explicit warm-up sets; every isWarmup
        // set on a trainer day is one Tempo added. Off = build none of them.
        let includeWarmups = program.warmupsEnabled
        // §4 — needed to tell whether today's number differs from the
        // trainer's because of a pain-flagged note (vs. recovery alone).
        let signals = noteSignals(modelContext: modelContext)

        for (order, item) in day.exercises.enumerated() {
            let exercise: Exercise
            if let id = item.exerciseID, let known = byID[id] {
                exercise = known
            } else if let known = byName[Self.normalizedName(item.name)] {
                exercise = known
            } else {
                // Unmatched on import (or library changed since) — keep the
                // trainer's name as a custom exercise, editable in the library.
                exercise = Exercise(
                    name: item.name,
                    muscleGroup: .fullBody,
                    equipment: .none,
                    movementPattern: .isolation,
                    isCompound: false,
                    isCustom: true
                )
                modelContext.insert(exercise)
                byID[exercise.id] = exercise
                byName[Self.normalizedName(item.name)] = exercise
            }

            let slot = PlannedExercise(order: order, workoutPlan: plan, exercise: exercise)
            slot.supersetGroup = item.group
            slot.restSecondsOverride = item.restSeconds
            // Fix #9 — a real flag, not just baked-in note text: drives the
            // "/ side" reps copy and the ×2 volume rule everywhere a set's
            // tonnage is read (see PlannedSet.volume).
            slot.perSide = item.perSide == true
            slot.programNote = item.notes?.nilIfEmpty

            // §5 — a % with no reliable e1RM (or an isolation/machine lift) is
            // read as EFFORT, not a weight guess: no fixed weight, a
            // calibration first set, and an RIR derived from the Epley
            // reps-at-% relationship.
            let isEffort = Self.isEffortPercent(item, exercise: exercise)
            let trainerTargetKg = Self.programWeightKg(item, exercise: exercise)
            let rpeRIR = item.rpe.map { max(0, Int((10 - $0).rounded())) }
            let effortRIR = (isEffort ? item.percentOf1RM : nil)
                .map { Self.effortTargetRIR(percent: $0, targetReps: item.targetReps) }

            slot.sets = prescribedSets(
                for: exercise,
                workingSets: max(1, item.sets),
                plan: plan,
                plannedExercise: slot,
                modelContext: modelContext,
                targetReps: item.targetReps,
                fixedWeightKg: trainerTargetKg,
                targetRIR: rpeRIR ?? effortRIR,
                applyDeload: false,
                isEffortOnly: isEffort,
                includeWarmups: includeWarmups
            )

            // §4 — record the trainer's own number and why Tempo changed it
            // (if it did), so the adjustment is never a silent substitution.
            if let trainerTargetKg {
                slot.trainerTargetKg = trainerTargetKg
                slot.loadAdjustmentNote = Self.loadAdjustmentNote(
                    trainerTargetKg: trainerTargetKg,
                    appliedWorkingWeightKg: slot.sets?.first(where: { !$0.isWarmup })?.targetWeight,
                    recoveryAdjustment: plan.recoveryAdjustment,
                    isConservativeNote: signals[exercise.id]?.isConservative == true
                )
            }
        }
        return true
    }

    /// §5 post-calibration propagation — a calibration set (`PlannedSet.
    /// isCalibration`) just told us the athlete's real number. Derive an
    /// e1RM (Epley) from what was actually logged and set every remaining,
    /// not-yet-completed set on the SAME exercise to a target weight for ITS
    /// OWN reps, snapped to a loadable weight in the user's unit/equipment.
    func propagateCalibration(
        from set: PlannedSet,
        weight: Double,
        reps: Int,
        modelContext: ModelContext
    ) {
        guard let plannedExercise = set.plannedExercise, let exercise = plannedExercise.exercise else {
            return
        }
        let e1RM = StrengthStandards.epleyE1RM(weight: weight, reps: reps)
        guard e1RM > 0 else {
            return
        }
        let unit = currentWeightUnit(modelContext: modelContext)
        for remaining in plannedExercise.orderedSets where !remaining.completed && remaining.id != set.id {
            let target = StrengthStandards.inverseEpleyWeight(e1RM: e1RM, reps: remaining.targetReps)
            remaining.targetWeight = WeightConverter.loadableKg(target, equipment: exercise.equipment, unit: unit)
        }
    }

    /// §4 — restores the trainer's own number (`trainerTargetKg`) for this
    /// exercise's remaining, not-yet-completed sets today — warm-ups re-ramp
    /// off it (same 50%/75% split as generation), working sets take it
    /// directly, both snapped to a loadable weight. Records the override so
    /// Today/the summary can show it was used instead of Tempo's adjustment.
    func useTrainerWeight(for plannedExercise: PlannedExercise, modelContext: ModelContext) {
        guard let target = plannedExercise.trainerTargetKg, target > 0,
              let exercise = plannedExercise.exercise,
              let plan = plannedExercise.workoutPlan,
              plan.status == .planned || plan.status == .inProgress
        else {
            return
        }
        let unit = currentWeightUnit(modelContext: modelContext)
        let pendingWarmups = plannedExercise.orderedSets.filter { $0.isWarmup && !$0.completed }
        for (index, warmup) in pendingWarmups.enumerated() {
            let fraction = pendingWarmups.count == 2 ? (index == 0 ? 0.5 : 0.75) : 0.75
            warmup.targetWeight = WeightConverter.loadableKg(
                target * fraction, equipment: exercise.equipment, unit: unit
            )
        }
        for workingSet in plannedExercise.orderedSets where !workingSet.isWarmup && !workingSet.completed {
            workingSet.targetWeight = WeightConverter.loadableKg(target, equipment: exercise.equipment, unit: unit)
        }
        plannedExercise.trainerOverrideApplied = true
        saveGuarded(modelContext, operation: "trainer weight override")
        HapticManager.selection()
        // Today + the active workout read the plan's exercises directly.
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
    }

    /// The trainer's load in kg: explicit weight, else % of the lifter's
    /// RELIABLE estimated 1RM (§5 — ≥1 logged working set in the last ~90
    /// days), else nil. nil covers both "no % written" (Tempo prescribes from
    /// history) and "% written but unreadable as a weight" (§5 effort path —
    /// see `isEffortPercent`); an isolation/machine lift's % is NEVER read as
    /// e1RM × %, even with a reliable max on file.
    nonisolated static func programWeightKg(_ item: ProgramExercise, exercise: Exercise) -> Double? {
        if let weight = item.weightKg, weight > 0 {
            return weight
        }
        guard let pct = item.percentOf1RM, pct > 0, !isIsolationOrMachine(exercise) else {
            return nil
        }
        guard let e1RM = reliableEstimated1RM(for: exercise), e1RM > 0 else {
            return nil
        }
        return e1RM * min(pct, 1.1)
    }

    /// §5 — true when the trainer wrote a %1RM that must be read as an
    /// EFFORT target (RIR + calibration) rather than a weight: no explicit
    /// weight, and `programWeightKg` couldn't resolve a number for it (no
    /// reliable e1RM, or an isolation/machine lift).
    nonisolated static func isEffortPercent(_ item: ProgramExercise, exercise: Exercise) -> Bool {
        guard let pct = item.percentOf1RM, pct > 0, (item.weightKg ?? 0) <= 0 else {
            return false
        }
        return programWeightKg(item, exercise: exercise) == nil
    }

    /// Machine/cable equipment, or any non-compound (isolation) lift — §5:
    /// a "1RM" on a stack or an isolation movement isn't a real one-rep max,
    /// so a trainer's % on one is ALWAYS effort, never e1RM × %.
    nonisolated static func isIsolationOrMachine(_ exercise: Exercise) -> Bool {
        !exercise.isCompound || exercise.equipment == .machine || exercise.equipment == .cable
    }

    /// §5 reliability gate — the most recent logged e1RM for `exercise`, but
    /// ONLY if it came from a working set logged within the last ~90 days.
    /// A stale e1RM (last trained months ago) isn't trustworthy enough to
    /// read a trainer's % against.
    nonisolated static func reliableEstimated1RM(for exercise: Exercise, asOf date: Date = Date()) -> Double? {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: date) ?? .distantPast
        return exercise.history?
            .filter { $0.date >= cutoff && ($0.estimated1RM ?? 0) > 0 }
            .max { $0.date < $1.date }?
            .estimated1RM
    }

    /// §5 — reps "possible" at `percent` of a true 1RM, via the same Epley
    /// relationship the rest of the app already uses, inverted: the rep
    /// count whose Epley e1RM equals `percent` of the max.
    nonisolated static func repsPossible(atPercent percent: Double) -> Int {
        guard percent > 0, percent < 1 else {
            return 1
        }
        return max(1, Int((30 * (1 - percent) / percent).rounded()))
    }

    /// §5 — effort target (reps in reserve) for a trainer % with no reliable
    /// e1RM: reps possible at that % (Epley) minus the prescribed reps.
    nonisolated static func effortTargetRIR(percent: Double, targetReps: Int) -> Int {
        max(0, repsPossible(atPercent: percent) - targetReps)
    }

    /// §4 — human reason today's trainer-day weight differs from the
    /// trainer's own number. nil when Tempo didn't change it (nothing to
    /// explain, nothing to show/override on Today).
    nonisolated static func loadAdjustmentNote(
        trainerTargetKg: Double,
        appliedWorkingWeightKg: Double?,
        recoveryAdjustment: Double,
        isConservativeNote: Bool
    ) -> String? {
        guard let applied = appliedWorkingWeightKg, applied < trainerTargetKg - 0.05 else {
            return nil
        }
        var reasons: [String] = []
        if recoveryAdjustment < 1.0 {
            let cutPercent = Int(((1 - recoveryAdjustment) * 100).rounded())
            reasons.append("Recovery yellow −\(cutPercent)%")
        }
        if isConservativeNote {
            reasons.append("Pain note — capped at last session")
        }
        guard !reasons.isEmpty else {
            return "Adjusted from your trainer's target"
        }
        return reasons.joined(separator: " · ")
    }

    nonisolated static func normalizedName(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
