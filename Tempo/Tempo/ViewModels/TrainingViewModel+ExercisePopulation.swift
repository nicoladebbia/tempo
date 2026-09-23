//
// TrainingViewModel+ExercisePopulation.swift
// Tempo
//
// Exercise selection + volume-prescription logic, split out of
// TrainingViewModel.swift to keep that file under the SwiftLint
// file/type-body length caps. Pure VM behavior — these are the same
// instance methods, just hosted in an extension. No signature or
// access-level changes; callers and tests are unaffected.
//
// Concern: given a WorkoutPlan's type + recovery state, pick the right
// exercises from the library (priority-ordered, day-seeded for
// variation), pair compatible supersets, and build PlannedExercise /
// PlannedSet objects with progressive-overload + recovery/deload-adjusted
// target weights.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    /// The user's display unit, read fresh from settings — prescriptions snap
    /// to weights loadable in THIS unit (see WeightConverter.loadableKg).
    /// Falls back to the VM property (set on loadToday) when settings are
    /// missing (fresh install, unit defaults to kg).
    func currentWeightUnit(modelContext: ModelContext) -> WeightUnit {
        (try? modelContext.fetch(FetchDescriptor<UserSettings>()))?.first?.weightUnit ?? weightUnit
    }

    /// Normalize a persisted plan's prescriptions onto the loadable lattice —
    /// covers plans generated before display-unit snapping existed, and plans
    /// generated under the other unit after a kg↔lbs switch. Idempotent
    /// (snapping a snapped value is a no-op); completed sets hold logged
    /// actuals and are never touched, and bodyweight lifts pass through
    /// (their "weight" is the lifter, not a load).
    func snapPrescribedWeights(for plan: WorkoutPlan, modelContext: ModelContext) {
        guard plan.status == .planned || plan.status == .inProgress else {
            return
        }
        let unit = currentWeightUnit(modelContext: modelContext)
        var changed = false
        for slot in plan.orderedExercises {
            guard let exercise = slot.exercise,
                  !StrengthStandards.isBodyweightLoaded(exercise.equipment)
            else {
                continue
            }
            for set in slot.orderedSets where !set.completed {
                guard let target = set.targetWeight, target > 0 else {
                    continue
                }
                let snapped = WeightConverter.loadableKg(target, equipment: exercise.equipment, unit: unit)
                if abs(snapped - target) > 0.001 {
                    set.targetWeight = snapped
                    changed = true
                }
            }
        }
        if changed {
            // Cosmetic re-snap, not user data — a failed save just leaves the
            // old numbers on screen until the next successful save.
            try? modelContext.save()
        }
    }

    // MARK: - Exercise Population

    // Populates a WorkoutPlan with exercises from the library based on workout type.

    func populateExercises(for plan: WorkoutPlan, modelContext: ModelContext) {
        guard plan.type.isGymWorkout else {
            return
        }
        guard plan.orderedExercises.isEmpty else {
            return
        } // already populated

        let targetGroups = muscleGroups(for: plan.type)
        guard !targetGroups.isEmpty else {
            return
        }

        // Phase 3: per-user learned weight increments, keyed by Exercise.id.
        // Empty for a new user → engine falls back to the equipment default.
        let learnedIncrements = adaptiveSignals(modelContext: modelContext).learnedIncrements

        // §19.3 — how a deload week lightens this session (weight vs sets;
        // fullRest never reaches here — those days became mobility upstream).
        let deloadStyle = loadDeloadSettings(modelContext: modelContext).style

        // Prescriptions snap to loadable weights in the user's display unit.
        let unit = currentWeightUnit(modelContext: modelContext)

        // Fetch all exercises from library
        var descriptor = FetchDescriptor<Exercise>()
        descriptor.sortBy = [SortDescriptor(\Exercise.name)]
        guard let allExercises = try? modelContext.fetch(descriptor) else {
            return
        }

        // Select exercises: priority-ordered compounds first, then isolations
        // — then substitute any movement the user has taught us they swap
        // (e.g. cable pushdown → their pushdown machine).
        let selected = applyPreferredSwaps(
            to: selectExercises(
                from: allExercises,
                targetGroups: targetGroups,
                workoutType: plan.type
            ),
            library: allExercises,
            modelContext: modelContext
        )

        // Assign superset groups for compatible exercise pairs.
        // Pair compound + isolation targeting different muscle groups (e.g. bench + lateral raise).
        let supersetPairs = assignSupersetGroups(selected)

        // Free-text note signals — recent user notes nudge the prescription:
        // pain / too-hard / form-breakdown hold conservative; "too easy" nudges
        // up. Pain subset is cached for the session UI. Scanned fresh each build
        // (no stored flag, no migration).
        let signals = noteSignals(modelContext: modelContext)
        let painFlagged = Set(signals.filter { $0.value.pain }.map(\.key))
        painFlaggedExercises = painFlagged

        // Build PlannedExercise + PlannedSet objects with target weights
        // Intelligent volume prescription:
        //   Primary compound (index 0): 4 working sets
        //   Secondary compounds (index 1-2): 3 working sets
        //   First isolation: 3 sets
        //   Remaining isolations: 2 sets
        // Target: 16-20 total working sets per session
        // Recovery-adjusted (yellow zone): reduce total volume by ~20%
        let isRecoveryReduced = plan.recoveryAdjustment < 1.0

        // Bodyweight (kg) for bodyweight-loaded lifts — the prescribed weight for
        // a pull-up/dip is EFFECTIVE (bodyweight ± added), and we record the
        // signed added-load suggestion per set. Fetched once per build.
        let bodyweightKg = currentBodyweightKg(modelContext: modelContext)

        // §2.16 — only the FIRST compound of the session earns the full
        // 50%/75% ramp (cold muscle, heaviest risk). Later compounds work
        // already-warm tissue: one 75% feel set. Isolations get none.
        var rampGiven = false

        for (index, exercise) in selected.enumerated() {
            let baseNumSets: Int
            if exercise.isCompound {
                baseNumSets = (index == 0) ? 4 : 3
            } else {
                // First isolation gets 3, rest get 2
                let compoundCount = selected.prefix(index).filter(\.isCompound).count
                let isolationIndex = index - compoundCount
                baseNumSets = (isolationIndex == 0) ? 3 : 2
            }

            // Recovery-adjusted: drop 1 set from compounds, keep isolations as-is
            let recoverySets: Int = if isRecoveryReduced && exercise.isCompound {
                max(2, baseNumSets - 1)
            } else {
                baseNumSets
            }

            // §19.3 volume-cut deload: same weights, half the working sets.
            let numSets: Int = if isDeloadWeek, deloadStyle == .volumeCut {
                max(1, (recoverySets + 1) / 2)
            } else {
                recoverySets
            }

            // Use progressive overload from history, or sensible defaults
            let history = exercise.history ?? []
            let overload = trainingEngine.calculateProgressiveOverload(
                for: exercise,
                history: history,
                learnedIncrement: learnedIncrements[exercise.id]
            )

            // §11.12 — e1RM-anchored prescription. With ≥2 scored sessions in
            // the window, the load comes from the rolling e1RM via reverse
            // Epley for the role's (reps @ RIR) scheme; a second same-type day
            // this week undulates to a volume scheme (DUP); a stalled lift
            // gets an 8% wave reset. Thin history → the legacy increment
            // engine, byte-for-byte the old behavior (targetRIR nil).
            let samples = history.map {
                PrescriptionMath.HistorySample(date: $0.date, e1RM: $0.estimated1RM)
            }
            let role: PrescriptionMath.Role = if exercise.isCompound {
                selected.prefix(index).contains(where: \.isCompound)
                    ? .secondaryCompound : .primaryCompound
            } else {
                .isolation
            }
            let scheme = PrescriptionMath.scheme(
                role: role, weekOccurrence: weekOccurrenceIndex(for: plan)
            )

            let reps: Int
            var targetRIR: Int?
            var weight: Double
            var rationale = overload.rationale
            if let e1RM = PrescriptionMath.currentE1RM(samples: samples) {
                reps = scheme.reps
                // Feedback backoff: last session maximal or form broke → one
                // more rep in reserve instead of a flat hold.
                var rir = scheme.rir
                if overload.rationale == .heldHighRPE || overload.rationale == .heldBrokenForm {
                    rir += 1
                }
                let plateaued = PrescriptionMath.isPlateaued(samples: samples)
                let anchor = plateaued ? e1RM * PrescriptionMath.plateauResetFactor : e1RM
                weight = PrescriptionMath.weight(e1RM: anchor, reps: reps, rir: rir)
                targetRIR = rir
                rationale = plateaued ? .plateauReset : .e1RMAnchored
            } else {
                reps = exercise.isCompound ? 8 : 12
                weight = overload.weight > 0
                    ? overload.weight
                    : coldStartWeight(
                        for: exercise,
                        targetReps: reps,
                        allExercises: allExercises,
                        modelContext: modelContext
                    )
            }

            // Note-driven adjustment. A conservative note (pain / too-hard / form
            // breakdown) → never prescribe MORE than last session's weight until
            // it clears. Otherwise a "too easy / too light" note → nudge up one
            // increment (catches "it felt light" typed without a logged low RPE;
            // the RPE path already handles the logged-RPE case).
            let sig = signals[exercise.id]
            if sig?.isConservative == true {
                // Hold conservative — never bump. Cap at last session's weight
                // when there is one; with no history just leave the (already
                // conservative) estimate as-is. Must NOT fall through to the
                // "too easy" bump even if the note also mentioned it (pain wins).
                if let lastWeight = history.sorted(by: { $0.date > $1.date }).first?.bestSetWeight,
                   lastWeight > 0 {
                    weight = min(weight, lastWeight)
                }
            } else if sig?.tooEasy == true {
                weight += StrengthStandards.increment(for: exercise.equipment)
            }

            // Apply recovery adjustment and deload multiplier if applicable.
            // Weight only drops on the intensity-cut style; volume-cut keeps
            // the load and halves the sets instead (§19.3).
            let deloadMultiplier = (isDeloadWeek && deloadStyle == .intensityCut)
                ? trainingEngine.deloadWeightMultiplier() : 1.0
            let adjustedWeight = weight * plan.recoveryAdjustment * deloadMultiplier
            // Snap to a weight that physically loads in the user's unit —
            // barbell plate math, machine stack pins, dumbbell rack steps.
            let roundedWeight = WeightConverter.loadableKg(
                adjustedWeight, equipment: exercise.equipment, unit: unit
            )

            // Bodyweight-loaded lift (pull-up/dip): the prescribed weight is the
            // EFFECTIVE load; the per-set added-load suggestion is the signed
            // difference from bodyweight (negative = assistance needed). nil when
            // bodyweight is unknown so the UI just treats it as bodyweight+0.
            let isBodyweightLift = StrengthStandards.isBodyweightLoaded(exercise.equipment)
            let plannedAddedLoad: Double? = {
                guard isBodyweightLift, let bw = bodyweightKg else {
                    return nil
                }
                return roundedWeight - bw
            }()

            // Look up superset group assignment
            let supersetGroup = supersetPairs[exercise.id]

            let planned = PlannedExercise(
                order: index,
                supersetGroup: supersetGroup,
                workoutPlan: plan,
                exercise: exercise
            )

            var plannedSets: [PlannedSet] = []
            var setNum = 1

            // Add warmup sets for compound exercises (ramp up to working weight).
            // Skipped for bodyweight lifts — a 50%/75% ramp of an effective
            // bodyweight load is not a loadable warmup (you can't do half a
            // pull-up); those warm up with assistance or bodyweight reps instead.
            if exercise.isCompound, roundedWeight > 0, !isBodyweightLift {
                // First compound: full 50%/75% ramp. Later compounds: one
                // 75% feel set — the muscle is already warm.
                let fractions = rampGiven ? [0.75] : [0.5, 0.75]
                rampGiven = true
                for fraction in fractions {
                    let warmupWeight = WeightConverter.loadableKg(
                        roundedWeight * fraction, equipment: exercise.equipment, unit: unit
                    )
                    plannedSets.append(PlannedSet(
                        setNumber: setNum,
                        targetReps: reps,
                        targetWeight: warmupWeight,
                        isWarmup: true,
                        plannedExercise: planned
                    ))
                    setNum += 1
                }
            }

            // Working sets
            for _ in 1 ... numSets {
                let ps = PlannedSet(
                    setNumber: setNum,
                    targetReps: reps,
                    targetWeight: roundedWeight,
                    targetRIR: targetRIR,
                    addedLoadKg: plannedAddedLoad,
                    plannedExercise: planned
                )
                plannedSets.append(ps)
                setNum += 1
            }
            planned.sets = plannedSets

            // Step 1 (measurement spine) — record what the engine just predicted
            // for this working exercise, so its accuracy can be measured against
            // the actual session later (persistCompletion backfills the outcome).
            // Passive ledger: nothing reads it to change prescriptions yet.
            // Step 4 shadow baseline: what the DUMB generic engine would have
            // prescribed — last logged weight + one fixed 2.5kg step, no
            // learning, no recovery/deload adjustment. nil when there's no prior
            // weight to project from (early sessions).
            let lastLoggedWeight = history.sorted(by: { $0.date > $1.date })
                .first?.bestSetWeight
            let baselineWeight: Double? = lastLoggedWeight.map { $0 + 2.5 }

            logPrediction(
                planID: plan.id,
                exercise: exercise,
                predictedWeight: roundedWeight,
                predictedReps: reps,
                rationale: rationale,
                learnedIncrement: learnedIncrements[exercise.id],
                baselineWeight: baselineWeight,
                modelContext: modelContext
            )
        }
    }

    /// §11.12 DUP — how many same-type days precede `plan` in ITS week.
    /// 0 = first occurrence (heavy schemes); ≥1 = volume day. weekPlans may
    /// be empty on the single-day fallback path → 0, the safe default.
    private func weekOccurrenceIndex(for plan: WorkoutPlan) -> Int {
        let cal = Calendar.current
        return weekPlans.count {
            $0.id != plan.id && $0.type == plan.type && $0.date < plan.date
                && cal.isDate($0.date, equalTo: plan.date, toGranularity: .weekOfYear)
        }
    }

    /// Write (or refresh) the PredictionLog row for one prescribed exercise.
    /// Idempotent per (workoutPlanID, exerciseID): re-running populateExercises
    /// for the same plan/exercise overwrites the prediction in place rather than
    /// accumulating duplicates. Only the most recent prescription is kept until
    /// the outcome is backfilled.
    private func logPrediction(
        planID: UUID,
        exercise: Exercise,
        predictedWeight: Double,
        predictedReps: Int,
        rationale: ProgressionReason,
        learnedIncrement: Double?,
        baselineWeight: Double?,
        modelContext: ModelContext
    ) {
        let exerciseID = exercise.id
        let descriptor = FetchDescriptor<PredictionLog>(
            predicate: #Predicate { $0.workoutPlanID == planID && $0.exerciseID == exerciseID }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        // Don't clobber a row that already has its outcome — that pairing is data.
        if let resolved = existing.first(where: { $0.outcomeResolved }) {
            _ = resolved
            return
        }
        // Replace any prior unresolved prediction for this plan+exercise.
        for stale in existing where !stale.outcomeResolved {
            modelContext.delete(stale)
        }
        let log = PredictionLog(
            exercise: exercise,
            exerciseID: exerciseID,
            workoutPlanID: planID,
            predictedWeight: predictedWeight,
            predictedReps: predictedReps,
            signalUsedRaw: rationale.rawValue,
            learnedIncrementUsed: learnedIncrement,
            baselineWeight: baselineWeight
        )
        modelContext.insert(log)
    }

    /// Assigns superset group IDs to compatible exercise pairs.
    /// Pairs a compound exercise with an isolation exercise targeting a different muscle group.
    /// Returns a dictionary mapping exercise ID to superset group number.
    func assignSupersetGroups(_ exercises: [Exercise]) -> [UUID: Int] {
        var assignments: [UUID: Int] = [:]
        var groupCounter = 1
        var paired = Set<UUID>()

        for (i, ex1) in exercises.enumerated() {
            guard !paired.contains(ex1.id) else {
                continue
            }
            guard ex1.isCompound else {
                continue
            }

            // Find the next isolation exercise targeting a different muscle group
            for j in (i + 1) ..< exercises.count {
                let ex2 = exercises[j]
                guard !paired.contains(ex2.id) else {
                    continue
                }
                guard !ex2.isCompound else {
                    continue
                }
                guard ex2.muscleGroup != ex1.muscleGroup else {
                    continue
                }

                // Pair found
                assignments[ex1.id] = groupCounter
                assignments[ex2.id] = groupCounter
                paired.insert(ex1.id)
                paired.insert(ex2.id)
                groupCounter += 1
                break
            }
        }

        return assignments
    }

    /// Maps workout type to the target muscle groups to train.
    func muscleGroups(for type: WorkoutType) -> [MuscleGroup] {
        switch type {
        case .push: [.chest, .shoulders, .triceps]
        case .pull: [.back, .biceps]
        case .legs: [.quads, .hamstrings, .glutes, .calves]
        case .upper: [.chest, .back, .shoulders, .biceps, .triceps]
        case .lower: [.quads, .hamstrings, .glutes, .calves]
        case .fullBody: [.chest, .back, .shoulders, .quads, .hamstrings, .glutes]
        default: []
        }
    }

    /// Selects exercises from the library for a given workout type.
    /// Uses priority ordering per workout type and day-of-week seed for variation.
    /// Returns 5-6 exercises: compounds first, then isolations.
    func selectExercises(
        from allExercises: [Exercise],
        targetGroups: [MuscleGroup],
        workoutType: WorkoutType
    ) -> [Exercise] {
        let matching = allExercises.filter { targetGroups.contains($0.muscleGroup) }
        let compounds = matching.filter(\.isCompound)
        let isolations = matching.filter { !$0.isCompound }

        // Priority ordering per workout type — ensures best exercise selection
        let priorityOrder = exercisePriorityOrder(for: workoutType)

        // Day-of-week seed for variation (so Monday Push != Thursday Push)
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let variationSeed = dayOfYear

        var selected: [Exercise] = []
        var usedNames = Set<String>()

        // Phase 1: Pick compounds in priority order (2-3 compounds)
        let maxCompounds = 3
        for priorityName in priorityOrder where selected.count < maxCompounds {
            if let match = compounds.first(where: {
                $0.name == priorityName && !usedNames.contains($0.name)
            }) {
                selected.append(match)
                usedNames.insert(match.name)
            }
        }

        // Phase 2: Fill remaining compound slots from target groups if priority didn't cover them
        for group in targetGroups where selected.count < maxCompounds {
            let groupCompounds = compounds.filter {
                $0.muscleGroup == group && !usedNames.contains($0.name)
            }
            // Use variation seed to rotate through available compounds
            if !groupCompounds.isEmpty {
                let pick = groupCompounds[variationSeed % groupCompounds.count]
                selected.append(pick)
                usedNames.insert(pick.name)
            }
        }

        // Phase 3: Pick isolations in priority order (fill to 5-6 total)
        let targetTotal = 6
        for priorityName in priorityOrder where selected.count < targetTotal {
            if let match = isolations.first(where: {
                $0.name == priorityName && !usedNames.contains($0.name)
            }) {
                selected.append(match)
                usedNames.insert(match.name)
            }
        }

        // Phase 4: Fill remaining isolation slots from target groups with variation
        for group in targetGroups where selected.count < targetTotal {
            let groupIsolations = isolations.filter {
                $0.muscleGroup == group && !usedNames.contains($0.name)
            }
            if !groupIsolations.isEmpty {
                let pick = groupIsolations[variationSeed % groupIsolations.count]
                selected.append(pick)
                usedNames.insert(pick.name)
            }
        }

        // Phase 5: If still under 5, add any remaining isolations
        for iso in isolations where selected.count < 5 {
            if !usedNames.contains(iso.name) {
                selected.append(iso)
                usedNames.insert(iso.name)
            }
        }

        return selected
    }

    /// Priority exercise ordering per workout type.
    /// Compounds listed first, then isolations in recommended order.
    func exercisePriorityOrder(for workoutType: WorkoutType) -> [String] {
        switch workoutType {
        case .push:
            [
                // Compounds
                "Barbell Bench Press", "Overhead Press", "Incline Dumbbell Press",
                // Isolations
                "Lateral Raise", "Tricep Pushdown", "Skull Crusher",
                "Cable Fly", "Cable Lateral Raise", "Overhead Tricep Extension",
            ]
        case .pull:
            [
                // Compounds
                "Barbell Row", "Pull-Up", "Lat Pulldown",
                // Isolations
                "Face Pull", "Barbell Curl", "Hammer Curl",
                "Cable Curl", "Rear Delt Fly", "Straight-Arm Pulldown",
            ]
        case .legs:
            [
                // Compounds
                "Barbell Back Squat", "Leg Press", "Romanian Deadlift",
                // Isolations
                "Leg Curl", "Standing Calf Raise", "Leg Extension",
                "Seated Leg Curl", "Seated Calf Raise", "Bulgarian Split Squat",
            ]
        case .upper:
            [
                "Barbell Bench Press", "Barbell Row", "Overhead Press",
                "Lat Pulldown", "Lateral Raise", "Barbell Curl",
                "Tricep Pushdown",
            ]
        case .lower:
            [
                "Barbell Back Squat", "Romanian Deadlift", "Leg Press",
                "Leg Curl", "Standing Calf Raise", "Leg Extension",
                "Hip Thrust",
            ]
        case .fullBody:
            [
                "Barbell Back Squat", "Barbell Bench Press", "Barbell Row",
                "Overhead Press", "Romanian Deadlift", "Lateral Raise",
            ]
        default:
            []
        }
    }

    // MARK: - Cold-start weight (e1RM-based)

    /// Target working weight (kg) for an exercise with no usable history, derived
    /// from an estimated 1RM and the target reps. Replaces the old flat
    /// per-equipment table (which made a barbell squat and a barbell overhead
    /// press BOTH start at 40 kg — the "some weights way too high, others way too
    /// low" complaint). Cascade, each step biased low so a wrong guess errs light:
    ///   1. Infer from a SIBLING lift the user has already trained (same movement
    ///      pattern + load basis) via a strength ratio.
    ///   2. Else a bodyweight × experience baseline (barbell-family compounds and
    ///      bodyweight movements) or a conservative absolute seed (dumbbell /
    ///      cable / machine / isolations).
    /// The e1RM is then derived DOWN to the working weight for `targetReps` via
    /// the inverse of the Epley formula the rest of the app uses, so the weight
    /// always matches the reps we actually prescribe. See `StrengthStandards`.
    func coldStartWeight(
        for exercise: Exercise,
        targetReps: Int,
        allExercises: [Exercise],
        modelContext: ModelContext
    ) -> Double {
        let bodyweight = currentBodyweightKg(modelContext: modelContext)
        let experience = currentExperienceLevel(modelContext: modelContext)

        let e1RM = crossExerciseE1RM(for: exercise, allExercises: allExercises)
            ?? StrengthStandards.baselineE1RM(
                for: exercise,
                bodyweightKg: bodyweight,
                experienceLevel: experience
            )

        let raw = StrengthStandards.inverseEpleyWeight(e1RM: e1RM, reps: targetReps)
        return StrengthStandards.roundToIncrement(raw, equipment: exercise.equipment)
    }

    /// Infer an e1RM for a never-trained exercise from a SIBLING lift (same
    /// movement pattern, same load basis) the user HAS logged. Picks the sibling
    /// whose history is freshest. Returns nil when there is no usable sibling so
    /// the caller falls through to the bodyweight/absolute baseline.
    private func crossExerciseE1RM(for exercise: Exercise, allExercises: [Exercise]) -> Double? {
        let candidates = allExercises.filter { other in
            other.id != exercise.id
                && other.movementPatternRaw == exercise.movementPatternRaw
                && StrengthStandards.shareLoadBasis(exercise, other)
                && (other.currentEstimated1RM ?? 0) > 0
        }
        let freshest = candidates.max { a, b in
            (a.history?.map(\.date).max() ?? .distantPast)
                < (b.history?.map(\.date).max() ?? .distantPast)
        }
        guard let freshest, let siblingE1RM = freshest.currentEstimated1RM else {
            return nil
        }
        return StrengthStandards.siblingE1RM(
            target: exercise, sibling: freshest, siblingE1RM: siblingE1RM
        )
    }

    /// User bodyweight (kg) for cold-start estimation. Explicit profile weight
    /// first, then the most recent HealthKit body-mass snapshot. nil when neither
    /// exists → `StrengthStandards` falls back to a conservative absolute seed.
    private func currentBodyweightKg(modelContext: ModelContext) -> Double? {
        if let profile = try? modelContext.fetch(FetchDescriptor<UserProfile>()).first,
           let w = profile.weightKg, w > 0 {
            return w
        }
        var descriptor = FetchDescriptor<BodyComposition>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let snap = try? modelContext.fetch(descriptor).first,
           let w = snap.weightKg, w > 0 {
            return w
        }
        return nil
    }

    // MARK: - Swap / Add Exercise (§2.13 / §2.14)

    /// Apply the user's remembered substitutions to a fresh selection: each
    /// selected exercise with a preference prescribes the replacement instead.
    /// A substitution is skipped when the replacement is already in the
    /// selection (no duplicate slots) or currently pain-flagged (safety wins
    /// over preference). Single-hop by design — the map was chain-collapsed
    /// on write, so no recursion here.
    func applyPreferredSwaps(
        to selection: [Exercise],
        library: [Exercise],
        modelContext: ModelContext
    ) -> [Exercise] {
        let prefs = (try? modelContext.fetch(FetchDescriptor<AdaptiveProfile>()))?
            .first?.preferredSwaps ?? [:]
        guard !prefs.isEmpty else {
            return selection
        }
        let byID = Dictionary(library.map { ($0.id, $0) }) { first, _ in first }
        let painFlagged = painFlaggedExerciseIDs(modelContext: modelContext)
        var chosen = Set(selection.map(\.id))
        return selection.map { exercise in
            guard let targetID = prefs[exercise.id],
                  let target = byID[targetID],
                  !chosen.contains(targetID),
                  !painFlagged.contains(targetID)
            else {
                return exercise
            }
            chosen.remove(exercise.id)
            chosen.insert(targetID)
            return target
        }
    }

    /// Remember a manual swap so future plans prescribe the user's pick.
    /// Chain-collapses: X→Y then (on a later plan) Y→Z stores X→Z, never a
    /// two-hop chain. Swapping BACK to the original forgets the preference
    /// instead of storing a loop. Caller persists (swapExercise saves).
    func rememberSwapPreference(from oldID: UUID, to newID: UUID, modelContext: ModelContext) {
        let profile = fetchOrCreateAdaptiveProfile(modelContext: modelContext)
        if let root = profile.preferredSwaps.first(where: { $0.value == oldID })?.key {
            if root == newID {
                profile.preferredSwaps.removeValue(forKey: root)
            } else {
                profile.preferredSwaps[root] = newID
            }
        } else {
            profile.preferredSwaps[oldID] = newID
        }
        profile.updatedAt = Date()
    }

    /// Alternatives offered by the swap sheet: same muscle group, not already
    /// in the plan. Closest substitutes first — same movement pattern, then
    /// same compound-ness, then name.
    func swapAlternatives(for plannedEx: PlannedExercise, modelContext: ModelContext) -> [Exercise] {
        guard let current = plannedEx.exercise, let plan = plannedEx.workoutPlan else {
            return []
        }
        let inPlan = Set(plan.orderedExercises.compactMap { $0.exercise?.id })
        let all = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        return all
            .filter { $0.muscleGroup == current.muscleGroup && !inPlan.contains($0.id) }
            .sorted { a, b in
                let aPattern = a.movementPatternRaw == current.movementPatternRaw
                let bPattern = b.movementPatternRaw == current.movementPatternRaw
                if aPattern != bPattern {
                    return aPattern
                }
                if a.isCompound != b.isCompound {
                    return a.isCompound == current.isCompound
                }
                return a.name < b.name
            }
    }

    /// §2.13 — replace a planned slot's movement in place. Keeps the slot
    /// (order, superset pairing) and the working-set COUNT already prescribed;
    /// reps/weights re-prescribe for the NEW movement from its own history or
    /// the cold-start model. Refuses once any set on the slot is completed —
    /// logged work must never be re-attributed to a different exercise.
    func swapExercise(
        _ plannedEx: PlannedExercise,
        with newExercise: Exercise,
        modelContext: ModelContext
    ) {
        guard let plan = plannedEx.workoutPlan,
              plan.status == .planned || plan.status == .inProgress,
              newExercise.id != plannedEx.exercise?.id,
              plannedEx.orderedSets.allSatisfy({ !$0.completed })
        else {
            return
        }

        let oldExerciseID = plannedEx.exercise?.id
        let workingCount = max(1, plannedEx.orderedSets.filter { !$0.isWarmup }.count)

        for stale in plannedEx.orderedSets {
            modelContext.delete(stale)
        }
        plannedEx.exercise = newExercise
        plannedEx.sets = prescribedSets(
            for: newExercise,
            workingSets: workingCount,
            plan: plan,
            plannedExercise: plannedEx,
            modelContext: modelContext
        )

        // The old movement's unresolved prediction can never be outcome-matched
        // now; prescribedSets logged the new one in its place.
        if let oldID = oldExerciseID {
            deleteUnresolvedPrediction(planID: plan.id, exerciseID: oldID, modelContext: modelContext)
            // Learn the substitution — future plans prescribe this pick.
            rememberSwapPreference(from: oldID, to: newExercise.id, modelContext: modelContext)
        }
        try? modelContext.save()
        HapticManager.selection()
    }

    /// §2.14 — append a chosen movement to today's plan with a full
    /// prescription (3 working sets, warmup ramp for loadable compounds).
    func addExercise(_ exercise: Exercise, modelContext: ModelContext) {
        guard let plan = todayPlan,
              plan.type.isGymWorkout,
              plan.status == .planned || plan.status == .inProgress,
              !plan.orderedExercises.contains(where: { $0.exercise?.id == exercise.id })
        else {
            return
        }

        let order = (plan.orderedExercises.map(\.order).max() ?? -1) + 1
        let planned = PlannedExercise(order: order, workoutPlan: plan, exercise: exercise)
        planned.sets = prescribedSets(
            for: exercise,
            workingSets: 3,
            plan: plan,
            plannedExercise: planned,
            modelContext: modelContext
        )
        try? modelContext.save()
        HapticManager.selection()
    }

    /// Shared prescription builder for swap/add — mirrors the per-exercise body
    /// of `populateExercises`: reps by compound-ness, weight from progressive
    /// overload falling back to cold-start, the plan's recovery + deload
    /// multipliers, 50%/75% warmup ramp for loadable compounds, bodyweight
    /// added-load hint. Also records the PredictionLog row (measurement spine).
    func prescribedSets(
        for exercise: Exercise,
        workingSets: Int,
        plan: WorkoutPlan,
        plannedExercise: PlannedExercise,
        modelContext: ModelContext
    ) -> [PlannedSet] {
        let reps = exercise.isCompound ? 8 : 12
        let learnedIncrements = adaptiveSignals(modelContext: modelContext).learnedIncrements
        let history = exercise.history ?? []
        let overload = trainingEngine.calculateProgressiveOverload(
            for: exercise,
            history: history,
            learnedIncrement: learnedIncrements[exercise.id]
        )
        let allExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        let weight = overload.weight > 0
            ? overload.weight
            : coldStartWeight(
                for: exercise,
                targetReps: reps,
                allExercises: allExercises,
                modelContext: modelContext
            )

        // §19.3 — same style split as populateExercises: intensity-cut drops
        // weight, volume-cut halves the requested working sets.
        let deloadStyle = loadDeloadSettings(modelContext: modelContext).style
        let deloadMultiplier = (isDeloadWeek && deloadStyle == .intensityCut)
            ? trainingEngine.deloadWeightMultiplier() : 1.0
        let effectiveWorkingSets = (isDeloadWeek && deloadStyle == .volumeCut)
            ? max(1, (workingSets + 1) / 2) : workingSets
        let adjusted = weight * plan.recoveryAdjustment * deloadMultiplier
        let unit = currentWeightUnit(modelContext: modelContext)
        let rounded = WeightConverter.loadableKg(adjusted, equipment: exercise.equipment, unit: unit)

        let isBodyweightLift = StrengthStandards.isBodyweightLoaded(exercise.equipment)
        let addedLoad: Double? = {
            guard isBodyweightLift, let bw = currentBodyweightKg(modelContext: modelContext) else {
                return nil
            }
            return rounded - bw
        }()

        var sets: [PlannedSet] = []
        var setNum = 1
        if exercise.isCompound, rounded > 0, !isBodyweightLift {
            // §2.16 — full 50%/75% ramp only when this is the plan's FIRST
            // compound; a swap/add landing after another compound works warm
            // muscle and gets one 75% feel set.
            let earlierCompoundExists = plan.orderedExercises.contains {
                $0.order < plannedExercise.order && $0.exercise?.isCompound == true
                    && $0.exercise?.id != exercise.id
            }
            for fraction in earlierCompoundExists ? [0.75] : [0.5, 0.75] {
                let warmupWeight = WeightConverter.loadableKg(
                    rounded * fraction, equipment: exercise.equipment, unit: unit
                )
                sets.append(PlannedSet(
                    setNumber: setNum,
                    targetReps: reps,
                    targetWeight: warmupWeight,
                    isWarmup: true,
                    plannedExercise: plannedExercise
                ))
                setNum += 1
            }
        }
        for _ in 1 ... max(1, effectiveWorkingSets) {
            sets.append(PlannedSet(
                setNumber: setNum,
                targetReps: reps,
                targetWeight: rounded,
                addedLoadKg: addedLoad,
                plannedExercise: plannedExercise
            ))
            setNum += 1
        }

        let lastLogged = history.sorted { $0.date > $1.date }.first?.bestSetWeight
        logPrediction(
            planID: plan.id,
            exercise: exercise,
            predictedWeight: rounded,
            predictedReps: reps,
            rationale: overload.rationale,
            learnedIncrement: learnedIncrements[exercise.id],
            baselineWeight: lastLogged.map { $0 + 2.5 },
            modelContext: modelContext
        )
        return sets
    }

    /// Drop the unresolved PredictionLog row for a plan+exercise pairing that
    /// no longer exists (the movement was swapped out before any outcome).
    func deleteUnresolvedPrediction(planID: UUID, exerciseID: UUID, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<PredictionLog>(
            predicate: #Predicate { $0.workoutPlanID == planID && $0.exerciseID == exerciseID }
        )
        for row in (try? modelContext.fetch(descriptor)) ?? [] where !row.outcomeResolved {
            modelContext.delete(row)
        }
    }

    /// Onboarding experience level ("Beginner"/"Intermediate"/"Advanced"),
    /// persisted to UserDefaults during onboarding. nil when never set → the
    /// strength model treats it as Beginner (the lowest, safest coefficient).
    private func currentExperienceLevel(modelContext: ModelContext) -> String? {
        // Durable home first (UserSettings). The onboarding UserDefaults blob is
        // deleted at completion, so it's only a fallback for the brief in-session
        // window before materialization — never rely on it post-onboarding.
        if let settings = try? modelContext.fetch(FetchDescriptor<UserSettings>()).first,
           let raw = settings.experienceLevelRaw, !raw.isEmpty {
            return raw
        }
        let data = UserDefaults.standard.dictionary(forKey: "tempo.onboarding.data")
        let raw = data?["experienceLevel"] as? String
        return (raw?.isEmpty ?? true) ? nil : raw
    }
}
