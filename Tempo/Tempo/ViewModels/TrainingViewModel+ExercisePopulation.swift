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

        // Fetch all exercises from library
        var descriptor = FetchDescriptor<Exercise>()
        descriptor.sortBy = [SortDescriptor(\Exercise.name)]
        guard let allExercises = try? modelContext.fetch(descriptor) else {
            return
        }

        // Select exercises: priority-ordered compounds first, then isolations
        let selected = selectExercises(
            from: allExercises,
            targetGroups: targetGroups,
            workoutType: plan.type
        )

        // Assign superset groups for compatible exercise pairs.
        // Pair compound + isolation targeting different muscle groups (e.g. bench + lateral raise).
        let supersetPairs = assignSupersetGroups(selected)

        // Tier 2.3 — exercises with a recent pain/injury note stay conservative
        // (no weight increase) until the note clears. Cached for the session UI.
        let painFlagged = painFlaggedExerciseIDs(modelContext: modelContext)
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
            let numSets: Int = if isRecoveryReduced && exercise.isCompound {
                max(2, baseNumSets - 1)
            } else {
                baseNumSets
            }

            let reps = exercise.isCompound ? 8 : 12

            // Use progressive overload from history, or sensible defaults
            let history = exercise.history ?? []
            let overload = trainingEngine.calculateProgressiveOverload(
                for: exercise,
                history: history,
                learnedIncrement: learnedIncrements[exercise.id]
            )
            var weight: Double = overload.weight > 0 ? overload.weight : defaultWeight(for: exercise)

            // Tier 2.3 — recent pain note on this exercise → never prescribe
            // MORE than last session's weight (hold conservative until it clears).
            if painFlagged.contains(exercise.id),
               let lastWeight = history.sorted(by: { $0.date > $1.date }).first?.bestSetWeight,
               lastWeight > 0 {
                weight = min(weight, lastWeight)
            }

            // Apply recovery adjustment and deload multiplier if applicable
            let deloadMultiplier = isDeloadWeek ? trainingEngine.deloadWeightMultiplier() : 1.0
            let adjustedWeight = weight * plan.recoveryAdjustment * deloadMultiplier
            let roundedWeight = (adjustedWeight / 2.5).rounded() * 2.5 // Round to nearest 2.5kg

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

            // Add warmup sets for compound exercises (ramp up to working weight)
            if exercise.isCompound, roundedWeight > 0 {
                // Warmup set 1: 50% working weight, same reps
                let warmup1Weight = ((roundedWeight * 0.5) / 2.5).rounded() * 2.5
                let ws1 = PlannedSet(
                    setNumber: setNum,
                    targetReps: reps,
                    targetWeight: warmup1Weight,
                    isWarmup: true,
                    plannedExercise: planned
                )
                plannedSets.append(ws1)
                setNum += 1

                // Warmup set 2: 75% working weight, same reps
                let warmup2Weight = ((roundedWeight * 0.75) / 2.5).rounded() * 2.5
                let ws2 = PlannedSet(
                    setNumber: setNum,
                    targetReps: reps,
                    targetWeight: warmup2Weight,
                    isWarmup: true,
                    plannedExercise: planned
                )
                plannedSets.append(ws2)
                setNum += 1
            }

            // Working sets
            for _ in 1 ... numSets {
                let ps = PlannedSet(
                    setNumber: setNum,
                    targetReps: reps,
                    targetWeight: roundedWeight,
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
                rationale: overload.rationale,
                learnedIncrement: learnedIncrements[exercise.id],
                baselineWeight: baselineWeight,
                modelContext: modelContext
            )
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

    /// Sensible starting weights (kg) when no history exists.
    func defaultWeight(for exercise: Exercise) -> Double {
        if exercise.isCompound {
            switch exercise.equipment {
            case .barbell: 40.0 // Empty bar + light plates
            case .dumbbell: 12.5 // Per hand
            case .cable: 25.0
            case .machine: 30.0
            default: 0 // Bodyweight
            }
        } else {
            switch exercise.equipment {
            case .barbell: 20.0
            case .dumbbell: 7.5
            case .cable: 15.0
            case .machine: 20.0
            default: 0 // Bodyweight
            }
        }
    }
}
