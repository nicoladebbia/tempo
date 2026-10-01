//
// TrainerFeedbackApplier.swift
// Tempo
//
// trainer-feedback-tests — matches each `RawTrainerFeedbackEdit` (from the
// AI step) against the CURRENT program week and turns it into a concrete,
// human-readable diff ("RDL: 60 kg → 65 kg", "Thu Anaerobic Run: skipped —
// knee") the review screen can toggle on/off. Pure and side-effect free,
// like `TrainerProgramParser`'s value conversion — WHICH day/exercise an
// edit means is decided here in Swift, deterministically, never left to the
// model to guess an index. An edit that can't be resolved to exactly one
// day/exercise is left unmatched ("couldn't match") for the athlete to fix
// by hand, never silently applied to the wrong row.
//
// Only the program's CURRENT week (`weekIndex`, e.g. `TrainerProgram
// .weekIndex(on: Date())`) is searched/edited — "adjust the current week"
// per the brief. A repeating single-week program has only one week, so this
// also is, in effect, permanent; for a multi-week block it affects only the
// week in progress.
//

import Foundation

// MARK: - ExerciseChanges

/// The field changes one `update_exercise` edit makes, applied on top of the
/// exercise as it is AT APPLY TIME (so two edits to the same exercise
/// compose, and two "+5 kg" deltas add up) instead of overwriting it with a
/// snapshot taken at resolve time.
struct ExerciseChanges: Equatable {
    var sets: Int?
    var repsLow: Int?
    var repsHigh: Int?
    var restSeconds: Int?
    /// Absolute weight; wins over `weightDeltaKg`.
    var weightKg: Double?
    var weightDeltaKg: Double?
    var notes: String?

    func applied(to exercise: ProgramExercise) -> ProgramExercise {
        var updated = exercise
        if let sets { updated.sets = sets }
        if let repsLow { updated.repsLow = repsLow }
        if let repsHigh { updated.repsHigh = repsHigh }
        if let restSeconds { updated.restSeconds = restSeconds }
        if let weightKg {
            updated.weightKg = weightKg
        } else if let weightDeltaKg {
            updated.weightKg = max(0, (exercise.weightKg ?? 0) + weightDeltaKg)
        }
        if let notes { updated.notes = notes }
        return updated
    }
}

// MARK: - ResolvedTrainerFeedbackEdit

struct ResolvedTrainerFeedbackEdit: Identifiable, Equatable {
    enum Action: Equatable {
        /// Exercises are addressed by their stable `ProgramExercise.id`, never
        /// by position: an earlier removal in the same batch shifts every
        /// later index, and two edits to one exercise must both land.
        case replaceExercise(weekIndex: Int, dayIndex: Int, exerciseID: UUID, changes: ExerciseChanges)
        case removeExercise(weekIndex: Int, dayIndex: Int, exerciseID: UUID)
        case addExercise(weekIndex: Int, dayIndex: Int, exercise: ProgramExercise)
        /// Sequence mode only: the day leaves the program (its exercises are
        /// emptied) — a weekday-less sequence has no "that Thursday" to skip.
        case skipDay(weekIndex: Int, dayIndex: Int)
        /// Fixed mode: skip only this DATE's occurrence; the program is
        /// untouched (see `TrainerProgramSkip`). Not a week mutation — the
        /// saver stores it via `skippedSessions(_:acceptedIDs:)`.
        case skipDate(weekIndex: Int, dayIndex: Int, date: Date)
        case moveDay(weekIndex: Int, dayIndex: Int, newWeekday: Int)
    }

    var id = UUID()
    /// "RDL: 60 kg → 65 kg" / "Thu Anaerobic Run: skipped — knee" style line.
    var summary: String
    /// nil means unmatched — `matchFailureReason` explains why.
    var action: Action?
    var matchFailureReason: String?

    var matched: Bool {
        action != nil
    }
}

// MARK: - TrainerFeedbackApplier

enum TrainerFeedbackApplier {
    /// Resolves every raw edit against `weeks[weekIndex]`. One
    /// `ResolvedTrainerFeedbackEdit` per raw edit, EXCEPT `update_exercise`/
    /// `remove_exercise` with no weekday given, which can match more than one
    /// occurrence (e.g. the same exercise on two days) — each occurrence
    /// becomes its own toggleable row.
    ///
    /// Edits resolve IN ORDER against a working copy that already reflects the
    /// earlier matched edits, so "remove X" then "change X" can't both match
    /// and a second edit's diff line starts from the first one's result.
    /// `scheduleMode` decides what "skip Thursday" means (fixed: only that
    /// date, via `.skipDate`; sequence: the day leaves the program);
    /// `referenceDate` anchors which week's Thursday is meant.
    static func resolve(
        edits: [RawTrainerFeedbackEdit],
        weeks: [ProgramWeek],
        weekIndex: Int,
        scheduleMode: TrainerProgramScheduleMode = .fixed,
        referenceDate: Date = Date()
    ) -> [ResolvedTrainerFeedbackEdit] {
        guard weeks.indices.contains(weekIndex) else {
            return edits.map {
                ResolvedTrainerFeedbackEdit(
                    summary: fallbackSummary($0),
                    action: nil,
                    matchFailureReason: "No current program week to apply this to."
                )
            }
        }
        var working = weeks
        let weekMonday = TrainingCalendar.mondayOfWeek(containing: referenceDate)
        var results: [ResolvedTrainerFeedbackEdit] = []
        for raw in edits {
            let resolved = resolve(raw, week: working[weekIndex], weekIndex: weekIndex, scheduleMode: scheduleMode, weekMonday: weekMonday)
            for edit in resolved {
                if let action = edit.action {
                    apply(action, to: &working)
                }
            }
            results.append(contentsOf: resolved)
        }
        return results
    }

    /// Applies every edit whose `id` is in `acceptedIDs`, in the order given
    /// (later edits see earlier ones' results — e.g. two accepted edits to
    /// the SAME exercise apply in sequence). Edits touching different weeks
    /// than `resolved` reports are never expected (`resolve` only ever
    /// targets one `weekIndex`), but every action still carries its own
    /// week/day/exercise indices defensively.
    static func apply(_ resolved: [ResolvedTrainerFeedbackEdit], acceptedIDs: Set<UUID>, to weeks: [ProgramWeek]) -> [ProgramWeek] {
        var weeks = weeks
        for edit in resolved where acceptedIDs.contains(edit.id) {
            guard let action = edit.action else {
                continue
            }
            apply(action, to: &weeks)
        }
        return weeks
    }

    /// The accepted dated skips (fixed mode), for the saver to store on the
    /// program. Pairs each with its edit's summary for the undo list.
    static func skippedSessions(
        _ resolved: [ResolvedTrainerFeedbackEdit],
        acceptedIDs: Set<UUID>,
        program: TrainerProgram
    ) -> [TrainerProgramSkip] {
        resolved.compactMap { edit in
            guard acceptedIDs.contains(edit.id), case let .skipDate(weekIndex, dayIndex, date)? = edit.action else {
                return nil
            }
            return TrainerProgramSkip(
                date: Calendar.current.startOfDay(for: date),
                sessionKey: program.sessionKey(weekIndex: weekIndex, dayIndex: dayIndex),
                summary: edit.summary
            )
        }
    }

    private static func apply(_ action: ResolvedTrainerFeedbackEdit.Action, to weeks: inout [ProgramWeek]) {
        switch action {
        case let .replaceExercise(weekIndex, dayIndex, exerciseID, changes):
            guard weeks.indices.contains(weekIndex), weeks[weekIndex].days.indices.contains(dayIndex),
                  let index = weeks[weekIndex].days[dayIndex].exercises.firstIndex(where: { $0.id == exerciseID })
            else {
                return
            }
            weeks[weekIndex].days[dayIndex].exercises[index] = changes.applied(to: weeks[weekIndex].days[dayIndex].exercises[index])
        case let .removeExercise(weekIndex, dayIndex, exerciseID):
            guard weeks.indices.contains(weekIndex), weeks[weekIndex].days.indices.contains(dayIndex),
                  let index = weeks[weekIndex].days[dayIndex].exercises.firstIndex(where: { $0.id == exerciseID })
            else {
                return
            }
            weeks[weekIndex].days[dayIndex].exercises.remove(at: index)
        case let .addExercise(weekIndex, dayIndex, exercise):
            guard weeks.indices.contains(weekIndex), weeks[weekIndex].days.indices.contains(dayIndex) else {
                return
            }
            weeks[weekIndex].days[dayIndex].exercises.append(exercise)
        case let .skipDay(weekIndex, dayIndex):
            // Emptying `exercises` is exactly what `TrainerProgram.sessions
            // (on:)`/`session(on:)` already treat as "nothing scheduled that
            // day" (both filter `!day.exercises.isEmpty`) — no separate
            // "skipped" flag needed for it to stop being scheduled.
            guard weeks.indices.contains(weekIndex), weeks[weekIndex].days.indices.contains(dayIndex) else {
                return
            }
            weeks[weekIndex].days[dayIndex].exercises = []
        case .skipDate:
            // Dated skips don't change the weeks — see `skippedSessions`.
            break
        case let .moveDay(weekIndex, dayIndex, newWeekday):
            guard weeks.indices.contains(weekIndex), weeks[weekIndex].days.indices.contains(dayIndex) else {
                return
            }
            weeks[weekIndex].days[dayIndex].weekday = newWeekday
            weeks[weekIndex].days[dayIndex].weekdayGuessed = false
        }
    }

    // MARK: - Per-edit resolution

    private static func resolve(
        _ raw: RawTrainerFeedbackEdit,
        week: ProgramWeek,
        weekIndex: Int,
        scheduleMode: TrainerProgramScheduleMode,
        weekMonday: Date
    ) -> [ResolvedTrainerFeedbackEdit] {
        switch raw.type {
        case .updateExercise:
            resolveExerciseEdit(raw, week: week, weekIndex: weekIndex)
        case .removeExercise:
            resolveExerciseEdit(raw, week: week, weekIndex: weekIndex)
        case .addExercise:
            [resolveAddExercise(raw, week: week, weekIndex: weekIndex)]
        case .skipSession:
            [resolveDayEdit(raw, week: week, weekIndex: weekIndex, scheduleMode: scheduleMode, weekMonday: weekMonday)]
        case .moveDay:
            [resolveDayEdit(raw, week: week, weekIndex: weekIndex, scheduleMode: scheduleMode, weekMonday: weekMonday)]
        }
    }

    // MARK: - Exercise-level edits (update / remove)

    private static func resolveExerciseEdit(
        _ raw: RawTrainerFeedbackEdit,
        week: ProgramWeek,
        weekIndex: Int
    ) -> [ResolvedTrainerFeedbackEdit] {
        guard let rawName = raw.exerciseName, !rawName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return [unmatched(raw, reason: "Which exercise?")]
        }
        let candidateDayIndices = dayIndices(matchingWeekday: raw.weekday, in: week)
        var matches: [(dayIndex: Int, exerciseIndex: Int)] = []
        for dayIndex in candidateDayIndices {
            for (exerciseIndex, exercise) in week.days[dayIndex].exercises.enumerated() where namesMatch(rawName, exercise.name) {
                matches.append((dayIndex, exerciseIndex))
            }
        }
        guard !matches.isEmpty else {
            return [unmatched(raw, reason: "Couldn't find \"\(rawName)\" this week.")]
        }

        return matches.map { dayIndex, exerciseIndex in
            let day = week.days[dayIndex]
            let exercise = day.exercises[exerciseIndex]
            switch raw.type {
            case .removeExercise:
                return ResolvedTrainerFeedbackEdit(
                    summary: "\(exercise.name): removed",
                    action: .removeExercise(weekIndex: weekIndex, dayIndex: dayIndex, exerciseID: exercise.id)
                )
            default:
                let (changes, diffs, refusal) = fieldChanges(raw, for: exercise)
                if let refusal {
                    return unmatched(raw, reason: refusal)
                }
                guard !diffs.isEmpty else {
                    return unmatched(raw, reason: "Nothing to change on \"\(exercise.name)\".")
                }
                return ResolvedTrainerFeedbackEdit(
                    summary: "\(exercise.name): \(diffs.joined(separator: ", "))",
                    action: .replaceExercise(weekIndex: weekIndex, dayIndex: dayIndex, exerciseID: exercise.id, changes: changes)
                )
            }
        }
    }

    /// The non-nil fields on `raw` that actually differ from `exercise`, plus
    /// a "field: old → new" line per change — so the review screen (and the
    /// applied change-log entry) show exactly what moved, never just
    /// "updated". `refusal` is set when the edit can't be applied safely: a
    /// relative "+5 kg" on a lift with no fixed weight would prescribe 5 kg
    /// out of nothing, so it is left for the athlete to review by hand.
    private static func fieldChanges(_ raw: RawTrainerFeedbackEdit, for exercise: ProgramExercise) -> (ExerciseChanges, [String], String?) {
        var changes = ExerciseChanges()
        var diffs: [String] = []

        if let sets = raw.sets, sets != exercise.sets {
            diffs.append("\(exercise.sets) sets → \(sets) sets")
            changes.sets = sets
        }
        if let repsLow = raw.repsLow, repsLow != exercise.repsLow {
            diffs.append("\(exercise.repsLow) reps → \(repsLow) reps")
            changes.repsLow = repsLow
        }
        if let repsHigh = raw.repsHigh, repsHigh != exercise.repsHigh {
            diffs.append("\(exercise.repsHigh.map(String.init) ?? "—") reps high → \(repsHigh) reps high")
            changes.repsHigh = repsHigh
        }
        if let restSeconds = raw.restSeconds, restSeconds != exercise.restSeconds {
            diffs.append("rest \(exercise.restSeconds.map(String.init) ?? "—")s → \(restSeconds)s")
            changes.restSeconds = restSeconds
        }
        if let weightKg = raw.weightKg, weightKg > 0 {
            diffs.append("\(formattedKg(exercise.weightKg)) → \(formattedKg(weightKg))")
            changes.weightKg = weightKg
        } else if let delta = raw.weightDeltaKg, delta != 0 {
            guard let base = exercise.weightKg, base > 0 else {
                let signed = (delta > 0 ? "+" : "-") + formattedKg(abs(delta))
                return (changes, diffs, "\(exercise.name) has no fixed weight, so \(signed) can't be applied. Set a weight first.")
            }
            let new = max(0, base + delta)
            diffs.append("\(formattedKg(base)) → \(formattedKg(new))")
            changes.weightDeltaKg = delta
        }
        if let notes = raw.notes, !notes.isEmpty {
            diffs.append("note: \"\(notes)\"")
            changes.notes = notes
        }
        return (changes, diffs, nil)
    }

    // MARK: - Add exercise

    private static func resolveAddExercise(
        _ raw: RawTrainerFeedbackEdit,
        week: ProgramWeek,
        weekIndex: Int
    ) -> ResolvedTrainerFeedbackEdit {
        guard let name = raw.exerciseName, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return unmatched(raw, reason: "Which exercise to add?")
        }
        let candidates = dayIndices(matchingWeekday: raw.weekday, in: week)
        guard let dayIndex = uniqueDay(candidates, week: week, hintName: name) else {
            return unmatched(raw, reason: candidates.isEmpty ? "No session that day." : "Say which day to add it to.")
        }
        let newExercise = ProgramExercise(
            name: name,
            exerciseID: nil,
            sets: raw.sets ?? 3,
            repsLow: raw.repsLow ?? 10,
            repsHigh: raw.repsHigh,
            weightKg: raw.weightKg,
            restSeconds: raw.restSeconds,
            notes: raw.notes
        )
        let dayLabel = TrainerProgramView.shortWeekdayName(week.days[dayIndex].weekday)
        return ResolvedTrainerFeedbackEdit(
            summary: "\(dayLabel) \(week.days[dayIndex].title ?? "session"): added \(name)",
            action: .addExercise(weekIndex: weekIndex, dayIndex: dayIndex, exercise: newExercise)
        )
    }

    // MARK: - Day-level edits (skip / move)

    private static func resolveDayEdit(
        _ raw: RawTrainerFeedbackEdit,
        week: ProgramWeek,
        weekIndex: Int,
        scheduleMode: TrainerProgramScheduleMode,
        weekMonday: Date
    ) -> ResolvedTrainerFeedbackEdit {
        guard raw.weekday != nil else {
            return unmatched(raw, reason: "Which day?")
        }
        let candidates = dayIndices(matchingWeekday: raw.weekday, in: week)
        guard let dayIndex = uniqueDay(candidates, week: week, hintName: raw.exerciseName) else {
            return unmatched(
                raw,
                reason: candidates.isEmpty
                    ? "No session on that day."
                    : "More than one session that day — couldn't tell which."
            )
        }
        let day = week.days[dayIndex]
        let dayLabel = "\(TrainerProgramView.shortWeekdayName(day.weekday)) \(day.title ?? day.workoutType.displayName)"

        switch raw.type {
        case .skipSession:
            let reasonSuffix = raw.reason.map { " — \($0)" } ?? ""
            if scheduleMode == .fixed,
               let date = Calendar.current.date(byAdding: .day, value: day.weekday - 1, to: weekMonday)
            {
                // Only that date: a repeating program is back to normal next week.
                return ResolvedTrainerFeedbackEdit(
                    summary: "\(dayLabel): skipped this \(TrainerProgramView.shortWeekdayName(day.weekday))\(reasonSuffix)",
                    action: .skipDate(weekIndex: weekIndex, dayIndex: dayIndex, date: date)
                )
            }
            return ResolvedTrainerFeedbackEdit(
                summary: "\(dayLabel): skipped\(reasonSuffix)",
                action: .skipDay(weekIndex: weekIndex, dayIndex: dayIndex)
            )
        case .moveDay:
            guard let newWeekday = raw.moveToWeekday, (1 ... 7).contains(newWeekday) else {
                return unmatched(raw, reason: "Move it to which day?")
            }
            let newLabel = TrainerProgramView.shortWeekdayName(newWeekday)
            return ResolvedTrainerFeedbackEdit(
                summary: "\(dayLabel): moved \(TrainerProgramView.shortWeekdayName(day.weekday)) → \(newLabel)",
                action: .moveDay(weekIndex: weekIndex, dayIndex: dayIndex, newWeekday: newWeekday)
            )
        default:
            return unmatched(raw, reason: "Unrecognized change.")
        }
    }

    // MARK: - Shared matching helpers

    private static func dayIndices(matchingWeekday weekday: Int?, in week: ProgramWeek) -> [Int] {
        guard let weekday else {
            return Array(week.days.indices)
        }
        return week.days.indices.filter { week.days[$0].weekday == weekday }
    }

    /// A single unambiguous day: exactly one candidate, or — when there are
    /// several (a lift + conditioning pairing on the same weekday) — the one
    /// whose title/focus/exercise names best match `hintName`.
    private static func uniqueDay(_ candidates: [Int], week: ProgramWeek, hintName: String?) -> Int? {
        if candidates.count == 1 {
            return candidates[0]
        }
        guard candidates.count > 1, let hintName, !hintName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }
        let matching = candidates.filter { index in
            let day = week.days[index]
            if let title = day.title, namesMatch(hintName, title) {
                return true
            }
            return day.exercises.contains { namesMatch(hintName, $0.name) || namesMatch(hintName, $0.detail ?? "") }
        }
        return matching.count == 1 ? matching[0] : nil
    }

    /// Normalized equality or containment either way — the trainer's
    /// feedback text and the program's own `ProgramExercise.name` are
    /// usually the SAME wording (same trainer, same shorthand), so this
    /// deliberately doesn't reach for fuzzy/library matching.
    private static func namesMatch(_ a: String, _ b: String) -> Bool {
        let na = ExerciseMatcher.normalize(a)
        let nb = ExerciseMatcher.normalize(b)
        guard !na.isEmpty, !nb.isEmpty else {
            return false
        }
        return na == nb || na.contains(nb) || nb.contains(na)
    }

    private static func unmatched(_ raw: RawTrainerFeedbackEdit, reason: String) -> ResolvedTrainerFeedbackEdit {
        ResolvedTrainerFeedbackEdit(summary: fallbackSummary(raw), action: nil, matchFailureReason: "Couldn't match — \(reason)")
    }

    private static func fallbackSummary(_ raw: RawTrainerFeedbackEdit) -> String {
        let name = raw.exerciseName ?? "session"
        return switch raw.type {
        case .updateExercise: "Change \(name)"
        case .removeExercise: "Remove \(name)"
        case .addExercise: "Add \(name)"
        case .skipSession: "Skip \(name)"
        case .moveDay: "Move \(name)"
        }
    }

    private static func formattedKg(_ kg: Double?) -> String {
        guard let kg, kg > 0 else {
            return "unset"
        }
        return kg == kg.rounded() ? "\(Int(kg)) kg" : String(format: "%.1f kg", kg)
    }
}
