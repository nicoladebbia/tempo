//
// TrainingEngine.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation
import SwiftData

// MARK: - Training Engine (Real Implementation)

// Per MODULE_TRAINING.md Sections 15-19 — Workout generation, progressive overload,
// recovery adjustment, football integration, deload detection.

final class TrainingEngine: TrainingEngineProtocol, @unchecked Sendable {
    // MARK: - Constants

    // Per MODULE_TRAINING.md Section 16.2 — Standard weight increments

    private static let barbellIncrement: Double = 2.5
    private static let dumbbellIncrement: Double = 2.0
    private static let cableIncrement: Double = 2.5
    private static let defaultIncrement: Double = 2.5
    private static let deloadWeekInterval: Int = 5 // weeks

    // MARK: - Generate Workout

    // Per MODULE_TRAINING.md Section 15 — Full workout generation for a single day.

    func generateWorkout(
        for date: Date,
        recoveryScore: Double?,
        footballDays: ActiveDays,
        split: TrainingSplit
    ) -> WorkoutPlan {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)

        // Per MODULE_TRAINING.md Section 18 — Check football constraints
        let isFootballDay = footballDays.isActive(on: weekday)
        let isTMinus1 = isFootballTMinus1(date: date, footballDays: footballDays)
        let isTPlus1 = isFootballTPlus1(date: date, footballDays: footballDays)

        // Per MODULE_TRAINING.md Section 18.2 — T-0: locked to football
        if isFootballDay {
            return WorkoutPlan(
                date: date,
                type: .football,
                notes: "Match day — pre-match prep only"
            )
        }

        // Determine recovery zone
        let zone = classifyRecoveryZone(score: recoveryScore)

        // Per MODULE_TRAINING.md Section 17.2 — Red: mobility or rest
        if zone == .red {
            return WorkoutPlan(
                date: date,
                type: .mobility,
                recoveryAdjustment: 0.0,
                notes: "Recovery is low — 25-min mobility session"
            )
        }

        // Per MODULE_TRAINING.md Section 18.2 — T+1: recovery-dependent, no legs
        if isTPlus1 {
            if zone == .red {
                return WorkoutPlan(date: date, type: .rest, notes: "Rest after yesterday's match")
            }
            // Upper body only on T+1, even with green recovery
            let upperType = preferredUpperType(for: date, split: split)
            let adjustment = zone == .yellow ? 0.8 : 1.0
            return WorkoutPlan(
                date: date,
                type: upperType,
                recoveryAdjustment: adjustment,
                notes: "Upper body only — T+1 after football"
            )
        }

        // Determine workout type from split rotation
        var workoutType = nextWorkoutType(for: date, split: split)

        // Per MODULE_TRAINING.md Section 18.2 — T-1: no legs
        if isTMinus1, workoutType == .legs {
            workoutType = swapLegsForUpper(split: split)
        }

        // Apply recovery adjustment
        // Per MODULE_TRAINING.md Section 17.2
        let recoveryAdjustment: Double
        switch zone {
        case .green:
            recoveryAdjustment = 1.0
        case .yellow:
            let score = recoveryScore ?? 50
            if score >= 50 {
                // Upper yellow: -20% volume only
                recoveryAdjustment = 0.8
            } else {
                // Lower yellow: -20% volume, -5% weight
                recoveryAdjustment = 0.75
            }
        case .red:
            recoveryAdjustment = 0.6 // shouldn't reach here, handled above
        }

        return WorkoutPlan(
            date: date,
            type: workoutType,
            recoveryAdjustment: recoveryAdjustment,
            notes: zone == .yellow ? "Recovery-adjusted workout" : nil
        )
    }

    // MARK: - Adjust For Recovery

    // Per MODULE_TRAINING.md Section 17.2 — Apply volume/intensity adjustments

    func adjustForRecovery(plan: WorkoutPlan, score: Double) -> WorkoutPlan {
        let zone = classifyRecoveryZone(score: score)

        switch zone {
        case .red:
            plan.type = .mobility
            plan.recoveryAdjustment = 0.0
            plan.notes = "Recovery is low — mobility session instead"
        case .yellow:
            if score >= 50 {
                plan.recoveryAdjustment = 0.8
            } else {
                plan.recoveryAdjustment = 0.75
            }
            plan.notes = "Recovery-adjusted: reduced volume"
        case .green:
            plan.recoveryAdjustment = 1.0
        }

        return plan
    }

    // MARK: - Progressive Overload

    // Per MODULE_TRAINING.md Section 16 — 2-of-3 rule

    func calculateProgressiveOverload(
        for exercise: Exercise,
        history: [ExerciseHistory],
        learnedIncrement: Double? = nil
    ) -> ProgressionDecision {
        let defaultReps = exercise.isCompound ? 8 : 12
        // Phase 3: use the on-device learned increment when present, else the
        // equipment default. Learning tunes the STEP SIZE per user/exercise.
        let increment = learnedIncrement ?? weightIncrement(for: exercise.equipment)

        // Need at least 2 sessions of data
        let recentSessions = history.sorted { $0.date > $1.date }.prefix(3)
        guard recentSessions.count >= 2 else {
            // Not enough data — hold at the most recent session's target-rep
            // equivalent weight (e1RM-derived; see anchorWeight).
            let lastWeight = anchorWeight(from: recentSessions.first, reps: defaultReps)
            return ProgressionDecision(
                weight: lastWeight, reps: defaultReps,
                deltaApplied: 0, rationale: .heldInsufficientData
            )
        }

        let currentWeight = anchorWeight(from: recentSessions.first, reps: defaultReps)

        // Tier 2 — feedback gate. The MOST RECENT session that carries real
        // user feedback (feedbackSampleCount > 0) can veto a progression: if it
        // felt maximal (avgRPE >= 9) or form broke down (sloppy/failed), HOLD
        // even when reps were hit. Sessions with no entered feedback (legacy
        // rows, or sets the user didn't annotate) carry nil aggregates and are
        // skipped here — never treated as RPE 0 — so behaviour is unchanged
        // when there's no signal.
        let lastFeedback = recentSessions.first { $0.feedbackSampleCount > 0 }
        if let lastFeedback {
            if (lastFeedback.avgRPE ?? 0) >= 9 {
                return ProgressionDecision(
                    weight: currentWeight, reps: defaultReps,
                    deltaApplied: 0, rationale: .heldHighRPE
                )
            }
            let formBroke = lastFeedback.worstFormRaw
                .flatMap(FormQuality.init(rawValue:))?.isNegativeSignal ?? false
            if formBroke {
                return ProgressionDecision(
                    weight: currentWeight, reps: defaultReps,
                    deltaApplied: 0, rationale: .heldBrokenForm
                )
            }
        }

        // Per MODULE_TRAINING.md Section 16.1 — Count successful sessions
        // A session is successful if best set hit target reps at target weight
        var successCount = 0
        for session in recentSessions {
            if let bestReps = session.bestSetReps, bestReps >= defaultReps {
                successCount += 1
            }
        }

        // Per MODULE_TRAINING.md Section 16.1 — Decision. The Tier-2 gate above
        // governs WHETHER to progress; here we also SIZE the jump. A clean,
        // well-below-maximal session (avgRPE ≤ 6.5) earns a double increment
        // (clamped to exactly one extra step — never a runaway jump) so an
        // under-loaded lifter catches up instead of crawling +2.5kg/week. With
        // no entered feedback this falls through to the standard increment, so
        // behaviour is unchanged when there's no signal.
        if successCount >= 2 {
            let feltEasy = (lastFeedback?.avgRPE).map { $0 <= 6.5 } ?? false
            let multiplier: Double = feltEasy ? 2.0 : 1.0
            let delta = increment * multiplier
            return ProgressionDecision(
                weight: currentWeight + delta, reps: defaultReps,
                deltaApplied: delta,
                rationale: feltEasy ? .acceleratedEasyLoad : .standardProgression
            )
        } else if successCount == 0, recentSessions.count >= 3 {
            // Failed 3 sessions in a row — check if needs deload
            let avgReps = recentSessions.compactMap(\.bestSetReps)
                .reduce(0, +) / max(1, recentSessions.count)
            if avgReps < Int(Double(defaultReps) * 0.75) {
                // Decrease weight
                return ProgressionDecision(
                    weight: max(0, currentWeight - increment), reps: defaultReps,
                    deltaApplied: -increment, rationale: .deloadedRepeatedFailure
                )
            }
        }

        // Keep current weight
        return ProgressionDecision(
            weight: currentWeight, reps: defaultReps,
            deltaApplied: 0, rationale: .standardProgression
        )
    }

    /// Working-weight anchor for `reps`, derived from a session's stored e1RM
    /// (Epley) rather than the raw heaviest set. Fixes the weight/reps decoupling:
    /// a set ground out at 100 kg × 3 no longer anchors an 8-rep target at 100 kg
    /// — it anchors at the 8-rep equivalent of that e1RM. Falls back to
    /// `bestSetWeight` when a row carries no e1RM (legacy rows, unit-test
    /// fixtures), so rep-MATCHED history round-trips to exactly the logged weight
    /// and pre-e1RM behavior is preserved where there's no e1RM to use.
    private func anchorWeight(from session: ExerciseHistory?, reps: Int) -> Double {
        guard let session else {
            return 0
        }
        if let e1RM = session.estimated1RM, e1RM > 0 {
            return StrengthStandards.inverseEpleyWeight(e1RM: e1RM, reps: reps)
        }
        return session.bestSetWeight ?? 0
    }

    // MARK: - Conditioning Debt (rest prescription)

    // Per MODULE_TRAINING.md Section 17 — recovery score ≠ work capacity. When
    // recent sessions repeatedly gassed the user, lengthen rest even at green
    // recovery so the next session isn't sabotaged by under-recovery between sets.

    func restMultiplier(history: [ExerciseHistory]) -> Double {
        let recent = history.sorted { $0.date > $1.date }.prefix(3)
        // Count sessions where at least half the entered feedback was `.gassed`.
        let gassySessions = recent.compactMap(\.gassedFraction).filter { $0 >= 0.5 }
        return gassySessions.count >= 2 ? 1.25 : 1.0 // +25% rest under conditioning debt
    }

    // MARK: - PR Detection

    // Per MODULE_TRAINING.md Section 12 — Compare to historical bests

    func detectPersonalRecord(
        exercise: Exercise,
        weight: Double,
        reps: Int
    ) -> PersonalRecord? {
        guard weight > 0, reps > 0 else {
            return nil
        }

        // Calculate estimated 1RM using Brzycki formula
        let estimated1RM: Double = if reps == 1 {
            weight
        } else {
            weight * (36.0 / (37.0 - Double(reps)))
        }

        // Compare to all-time PR
        let currentPR = exercise.allTimePR ?? 0
        if estimated1RM > currentPR {
            return PersonalRecord(
                type: .oneRepMax,
                value: estimated1RM,
                date: Date(),
                context: "\(Int(weight))kg x \(reps) reps",
                exercise: exercise
            )
        }

        // Check rep max PR — highest weight at this rep count or above
        let records = exercise.personalRecords ?? []
        let repMaxPR = records
            .filter { $0.type == .repMax }
            .max { $0.value < $1.value }
        if weight > (repMaxPR?.value ?? 0), reps >= 3 {
            return PersonalRecord(
                type: .repMax,
                value: weight,
                date: Date(),
                context: "\(Int(weight))kg x \(reps) reps",
                exercise: exercise
            )
        }

        return nil
    }

    // MARK: - Generate Week Plan

    // Per MODULE_TRAINING.md Section 15.4 — Full week planning with football awareness

    func generateWeekPlan(
        startDate: Date,
        recoveryScores: [Date: Double],
        footballDays: ActiveDays,
        split: TrainingSplit,
        // Advanced custom split — a user-assigned WorkoutType per weekday
        // (Mon-first, length 7). Non-nil only when split == .custom and the user
        // configured it; then it supplies the type for each normal training day
        // (football / T+1 / red-recovery still apply on top, unchanged).
        customWeekdayMap: [WorkoutType]? = nil,
        recoveryThresholdOffset: Double = 0,
        // D3 — start-of-day keys of DATED matches (distinct from the recurring
        // footballDays weekdays). A match here makes that day T-0 (a session day)
        // even when it falls off a usual football weekday — the §14 mid-week-match
        // periodization.
        matchDayKeys: Set<Date> = [],
        // The subset of match days that are COMPETITIVE: only these drive the
        // T-1 taper (no heavy legs the day before). A friendly scrimmage is a
        // T-0 day but does NOT taper the day before. Defaults to all match days
        // (callers that don't distinguish get the safe "protect everything").
        competitiveMatchDayKeys: Set<Date>? = nil,
        // §14 Decision 1 — the declared block emphasis re-shapes how SPARE days
        // are spent: physique (default) keeps the pre-emphasis behavior exactly;
        // soccer turns spare capacity into soccer work (one conditioning day,
        // never beside a match, plus pool recovery) while gym days stay put
        // (strength held at maintenance, §12 — never fewer lifting days).
        emphasis: BlockEmphasis = .physique,
        // §14 auto-variety (requirement (d) "based on what he did before") — the
        // ORDER the spare-day EASY modality cycles through, learned from logged
        // history (see `easyModalityOrder(poolLogged:runLogged:)`). The user's
        // revealed-preferred modality leads; the other still appears for variety.
        // Defaults to the launch behavior (low-impact pool first).
        easyModalityPreference: [WorkoutType] = [.pool, .run],
        // "Today" for the §21 (b) two-a-day scheduler: the capped weekly slot is
        // never spent on a day already in the past (it can't be trained), so it
        // slides to the next eligible upper day. Injected (not Date() inline) to
        // keep the function pure for tests. Default = now for production callers.
        referenceDate: Date = Date()
    ) -> [WorkoutPlan] {
        let tMinus1MatchDays = competitiveMatchDayKeys ?? matchDayKeys
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: referenceDate)
        var plans: [WorkoutPlan] = []
        var splitIndex = 0
        var conditioningDaysAssigned = 0
        // §21 requirement (b) — how many GYM days this week also earned an easy
        // cardio SECOND session (a "two-a-day"). Capped: soccer emphasis is
        // already cardio-loaded by football, so it earns at most one; a physique
        // block (no football) can take two. Bounds weekly load so the auto-
        // decision never over-reaches.
        var twoADaysAssigned = 0
        let maxTwoADays = emphasis == .soccer ? 1 : 2
        // Alternates the easy cross-training modality (pool → run → pool …) by a
        // counter, NOT absolute weekday, so both modalities actually appear
        // instead of the parity skewing every easy day to one of them.
        var easyCrossTrainingAssigned = 0

        // Per MODULE_TRAINING.md Section 15.4 — Phase 1: Assign workout types to days
        let splitSequence = getSplitSequence(split)
        let trainingDaysNeeded = splitSequence.count

        // First pass: identify football days, T-1, T+1
        var dayMeta: [(date: Date, isFootball: Bool, isTMinus1: Bool, isTPlus1: Bool)] = []
        for offset in 0 ..< 7 {
            // Calendar.date(byAdding:) only returns nil on pathological
            // calendars; guard rather than force-unwrap so a boundary
            // date (DST, leap) can't crash week-plan generation.
            guard let date = cal.date(byAdding: .day, value: offset, to: startDate) else {
                continue
            }
            let weekday = cal.component(.weekday, from: date)
            // A day is "football" (T-0) if it's a recurring football weekday OR
            // a dated match. T-1 likewise fires the day before either. The dated
            // match widens the recurring-weekday rule; it never narrows it.
            let isMatch = MatchSchedule.isMatchDay(date: date, matchDayKeys: matchDayKeys, calendar: cal)
            let isMatchTMinus1 = MatchSchedule.isTMinus1(date: date, matchDayKeys: tMinus1MatchDays, calendar: cal)
            dayMeta.append((
                date: date,
                isFootball: footballDays.isActive(on: weekday) || isMatch,
                isTMinus1: isFootballTMinus1(date: date, footballDays: footballDays) || isMatchTMinus1,
                isTPlus1: isFootballTPlus1(date: date, footballDays: footballDays)
            ))
        }

        // Assign types
        for meta in dayMeta {
            // Per MODULE_TRAINING.md Section 18.2 — T-0. The note distinguishes
            // a DATED fixture ("Match day" — a real game) from a recurring
            // football weekday ("Football day" — training cadence); the week
            // row shows it verbatim, so the two §14 concepts stop conflating.
            if meta.isFootball {
                let isDatedMatch = MatchSchedule.isMatchDay(
                    date: meta.date, matchDayKeys: matchDayKeys, calendar: cal
                )
                plans.append(WorkoutPlan(
                    date: meta.date,
                    type: .football,
                    notes: isDatedMatch ? "Match day" : "Football day"
                ))
                continue
            }

            // Per-day recovery lookup (was: today-applied-to-every-day, which
            // painted the whole Week Plan as mobility/rest whenever Monday was
            // low). Missing day → nil → green default (matches single-day path).
            let dayKey = cal.startOfDay(for: meta.date)
            let dayRecoveryScore = recoveryScores[dayKey]
            let zone = classifyRecoveryZone(score: dayRecoveryScore, offset: recoveryThresholdOffset)

            // Per MODULE_TRAINING.md Section 18.2 — T+1
            if meta.isTPlus1 {
                switch zone {
                case .red:
                    plans.append(WorkoutPlan(
                        date: meta.date,
                        type: .rest,
                        notes: "Rest — T+1 after football"
                    ))
                case .yellow:
                    let score = dayRecoveryScore ?? 50
                    if score < 50 {
                        plans.append(WorkoutPlan(
                            date: meta.date,
                            type: .mobility,
                            notes: "Mobility — T+1 after football"
                        ))
                    } else {
                        let upperType = preferredUpperType(for: meta.date, split: split)
                        plans.append(WorkoutPlan(
                            date: meta.date,
                            type: upperType,
                            recoveryAdjustment: 0.8,
                            notes: "Reduced upper body — T+1"
                        ))
                        splitIndex += 1
                    }
                case .green:
                    // Upper body only even with green (neuromuscular impairment)
                    let upperType = preferredUpperType(for: meta.date, split: split)
                    plans.append(WorkoutPlan(
                        date: meta.date,
                        type: upperType,
                        notes: "Upper body only — T+1 after football"
                    ))
                    splitIndex += 1
                }
                continue
            }

            // Red recovery → mobility
            if zone == .red {
                plans.append(WorkoutPlan(
                    date: meta.date,
                    type: .mobility,
                    recoveryAdjustment: 0.0,
                    notes: "Recovery is low"
                ))
                continue
            }

            // Normal training day. For an advanced custom split the user maps a
            // type to each weekday (Mon-first); a valid map takes over here.
            // Football / T+1 / red-recovery already ran above, so the map only
            // supplies the type for an ordinary training day. An explicit .rest
            // is honoured verbatim (not auto-filled with active recovery).
            if split == .custom, let customMap = customWeekdayMap, customMap.count == 7 {
                let idx = (cal.component(.weekday, from: meta.date) + 5) % 7 // Mon=0…Sun=6
                let mapped = customMap[idx]
                if mapped != .rest {
                    var workoutType = mapped
                    if meta.isTMinus1 && workoutType == .legs {
                        workoutType = swapLegsForUpper(split: split)
                    }
                    let adjustment: Double = zone == .yellow
                        ? ((dayRecoveryScore ?? 50) >= 50 ? 0.8 : 0.75)
                        : 1.0
                    let customPlan = WorkoutPlan(
                        date: meta.date,
                        type: workoutType,
                        recoveryAdjustment: adjustment,
                        notes: zone == .yellow ? "Recovery-adjusted" : nil
                    )
                    // §21 (b) — a custom-split gym day earns a two-a-day on the
                    // SAME eligibility as the standard path (this branch used to
                    // skip it, so custom splits never got two-a-days).
                    if let secondary = twoADaySecondary(
                        workoutType: workoutType, zone: zone, isTMinus1: meta.isTMinus1,
                        isPast: cal.startOfDay(for: meta.date) < todayStart,
                        assignedSoFar: twoADaysAssigned, max: maxTwoADays,
                        preference: easyModalityPreference
                    ) {
                        customPlan.secondarySessionType = secondary
                        twoADaysAssigned += 1
                    }
                    plans.append(customPlan)
                } else {
                    plans.append(WorkoutPlan(date: meta.date, type: .rest))
                }
            } else if splitIndex < trainingDaysNeeded {
                var workoutType = splitSequence[splitIndex]

                // Per MODULE_TRAINING.md Section 18.2 — T-1: no legs
                if meta.isTMinus1 && workoutType == .legs {
                    workoutType = swapLegsForUpper(split: split)
                }

                let adjustment: Double = zone == .yellow
                    ? ((dayRecoveryScore ?? 50) >= 50 ? 0.8 : 0.75)
                    : 1.0

                let liftPlan = WorkoutPlan(
                    date: meta.date,
                    type: workoutType,
                    recoveryAdjustment: adjustment,
                    notes: zone == .yellow ? "Recovery-adjusted" : nil
                )

                // §21 requirement (b) — a gym day can carry an easy cardio SECOND
                // session (a two-a-day) when the body clearly has headroom. Same
                // shared eligibility as the custom-split path (green + upper lift +
                // not T-1 + under the weekly cap); modality = the learned (d)
                // leader. The daily brain still drops it on a low-readiness morning.
                if let secondary = twoADaySecondary(
                    workoutType: workoutType, zone: zone, isTMinus1: meta.isTMinus1,
                    isPast: cal.startOfDay(for: meta.date) < todayStart,
                    assignedSoFar: twoADaysAssigned, max: maxTwoADays,
                    preference: easyModalityPreference
                ) {
                    liftPlan.secondarySessionType = secondary
                    twoADaysAssigned += 1
                }

                plans.append(liftPlan)
                splitIndex += 1
            } else {
                // Spare capacity → standing auto cross-training (Slice 1).
                // Games, red-recovery and required lifts are handled above; here
                // zone is green/yellow with no lift scheduled. Sunday stays a
                // full rest day. Every other spare day becomes recovery-
                // appropriate cross-training so the week is VARIED (swim / easy
                // run) instead of idle — with a capped HARD conditioning day
                // under soccer emphasis only, never on T-1 or the day after legs
                // (protect the legs Nicola both trains and plays football on).
                let weekday = cal.component(.weekday, from: meta.date)
                let prevType = plans.last?.type
                let afterLegs = prevType == .legs || prevType == .lower
                // Physique = easy variety only (cap 0); soccer earns one hard day.
                let conditioningCap = emphasis == .soccer ? 1 : 0
                if weekday == 1 { // Sunday — protected full rest
                    plans.append(WorkoutPlan(date: meta.date, type: .rest))
                } else if zone == .green, !meta.isTMinus1, !afterLegs,
                          conditioningDaysAssigned < conditioningCap {
                    conditioningDaysAssigned += 1
                    plans.append(WorkoutPlan(
                        date: meta.date,
                        type: .conditioning,
                        durationMinutes: 30,
                        notes: "Cross-training — conditioning"
                    ))
                } else if meta.isTMinus1 {
                    // Pre-match: pool only — no leg-loading impact before a game.
                    plans.append(WorkoutPlan(
                        date: meta.date,
                        type: .pool,
                        durationMinutes: 20,
                        notes: "Pool — pre-match easy"
                    ))
                } else {
                    // Easy recovery cross-training; cycle the modality by a
                    // counter so the week genuinely varies. The ORDER is the
                    // learned preference (§14 requirement (d)) — the modality the
                    // user actually logs most leads; the other still appears.
                    // Empty guard keeps a valid cycle if a caller passes [].
                    let order = easyModalityPreference.isEmpty ? [.pool, .run] : easyModalityPreference
                    let easy = order[easyCrossTrainingAssigned % order.count]
                    easyCrossTrainingAssigned += 1
                    plans.append(WorkoutPlan(
                        date: meta.date,
                        type: easy,
                        durationMinutes: easy == .pool ? 45 : 30,
                        notes: easy == .pool ? "Pool — easy recovery" : "Easy run — Zone 2"
                    ))
                }
            }
        }

        return plans
    }

    /// Revealed cross-training preference — the ORDER the spare-day EASY modality
    /// cycles through, learned from what the user actually logs (§14 auto-variety,
    /// requirement (d) "based on what he did before"). Both modalities still
    /// appear for variety; the one he genuinely does more LEADS. A clear lean
    /// toward running (≥3 runs AND ≥2× the swims) promotes it — a real signal, not
    /// noise; otherwise the low-impact pool leads (the launch behavior, and the
    /// safe pick when history is thin or balanced). Pure — the caller supplies the
    /// counts from an `ActivitySession` history fetch.
    static func easyModalityOrder(poolLogged: Int, runLogged: Int) -> [WorkoutType] {
        if runLogged >= 3, runLogged >= poolLogged * 2 { return [.run, .pool] }
        return [.pool, .run]
    }

    // MARK: - Deload Detection

    // Every Nth week (configurable), generate a deload week.
    // Deload: reduce weights by 40%, keep reps the same.

    func isDeloadWeek(
        date: Date,
        deloadFrequencyWeeks: Int,
        trainingStartDate: Date?,
        fatigueEWMA: Double? = nil
    ) -> Bool {
        let cal = Calendar.current
        let startDate = trainingStartDate ?? cal.date(byAdding: .month, value: -3, to: date) ?? date
        let weeksSinceStart = cal.dateComponents([.weekOfYear], from: cal.startOfDay(for: startDate), to: cal.startOfDay(for: date))
            .weekOfYear ?? 0
        let frequency = max(1, deloadFrequencyWeeks)
        // Periodic baseline: week N, 2N, 3N… are deload weeks.
        let periodic = weeksSinceStart > 0 && (weeksSinceStart % frequency) == 0

        // Phase 3 (Fix 3.4) — fatigue-triggered EARLY deload. A sustained high
        // fatigue trend (mean session RPE creeping toward maximal) means the
        // fixed cycle is too slow for how this user is actually recovering.
        // Only EARNS an extra deload — never suppresses a scheduled one.
        let fatigueTriggered = (fatigueEWMA ?? 0) >= Self.fatigueDeloadThreshold

        return periodic || fatigueTriggered
    }

    /// Mean-RPE fatigue level at/above which an early deload is triggered. 8.5
    /// = sessions consistently feeling near-maximal — a clear over-reaching
    /// signal independent of the calendar.
    private static let fatigueDeloadThreshold: Double = 8.5

    func deloadWeightMultiplier() -> Double {
        0.6 // 40% reduction
    }

    // MARK: - Private Helpers

    // Recovery zone classification
    // Per CROSS_DOC_AUDIT.md canonical boundaries: Green >= 67, Yellow 34-66, Red < 34

    /// §21 (b) — the easy cardio SECOND session a gym day earns when it has clear
    /// headroom (GREEN recovery + an UPPER-body lift + not the day before a match
    /// + under the weekly cap), or nil for no two-a-day. Pure — the caller owns
    /// the running counter. Shared by the standard-split AND custom-split paths so
    /// the eligibility rule cannot diverge between them (the custom path used to
    /// omit it entirely, so a custom split never got two-a-days).
    private func twoADaySecondary(workoutType: WorkoutType, zone: RecoveryZone, isTMinus1: Bool,
                                  isPast: Bool, assignedSoFar: Int, max: Int,
                                  preference: [WorkoutType]) -> WorkoutType? {
        let upperLift = workoutType == .push || workoutType == .pull || workoutType == .upper
        // isPast: never spend the (capped) weekly slot on a day already gone — it
        // can't be trained, so it slides to the next eligible upper day.
        guard !isPast, zone == .green, upperLift, !isTMinus1, assignedSoFar < max else { return nil }
        let order = preference.isEmpty ? [.pool, .run] : preference
        return order[0] == .run ? .run : .pool
    }

    private func classifyRecoveryZone(score: Double?, offset: Double = 0) -> RecoveryZone {
        guard let score else {
            return .green
        } // default to green if no data
        // Phase 3: the learned per-user offset shifts the zone boundaries. It is
        // clamped to ±10 at the source (AdaptiveProfile.clampedThresholdOffset)
        // so a learned offset can never invert the safety meaning of red.
        let clampedOffset = min(max(offset, -10), 10)
        if score >= 67 + clampedOffset {
            return .green
        }
        if score >= 34 + clampedOffset {
            return .yellow
        }
        return .red
    }

    // Per MODULE_TRAINING.md Section 16.2 — Weight increment by equipment

    private func weightIncrement(for equipment: Equipment) -> Double {
        switch equipment {
        case .barbell: Self.barbellIncrement
        case .dumbbell: Self.dumbbellIncrement
        case .cable,
             .machine: Self.cableIncrement
        default: Self.defaultIncrement
        }
    }

    // Get the ordered split sequence for a training split
    // Per MODULE_TRAINING.md Section 15.4

    private func getSplitSequence(_ split: TrainingSplit) -> [WorkoutType] {
        switch split {
        case .pushPullLegs:
            [.push, .pull, .legs, .push, .pull, .legs]
        case .upperLower:
            [.upper, .lower, .upper, .lower]
        case .fullBody:
            [.fullBody, .fullBody, .fullBody]
        case .bro:
            [.push, .pull, .legs, .push, .pull]
        case .custom:
            [.push, .pull, .legs] // fallback
        }
    }

    // Determine next workout type for a given date based on split rotation
    // Uses day-of-week for deterministic rotation

    private func nextWorkoutType(for date: Date, split: TrainingSplit) -> WorkoutType {
        let cal = Calendar.current
        let dayOfYear = cal.ordinality(of: .day, in: .year, for: date) ?? 0
        let sequence = getSplitSequence(split)
        guard !sequence.isEmpty else {
            return .push
        }
        return sequence[dayOfYear % sequence.count]
    }

    // Swap legs for an upper body type based on split
    // Per MODULE_TRAINING.md Section 18.2 — T-1 swap

    private func swapLegsForUpper(split: TrainingSplit) -> WorkoutType {
        switch split {
        case .pushPullLegs,
             .bro,
             .custom:
            .push
        case .upperLower:
            .upper
        case .fullBody:
            .upper
        }
    }

    // Get preferred upper body type for T+1 days
    // Per MODULE_TRAINING.md Section 18.2 — Prefer Pull on T+1

    private func preferredUpperType(for date: Date, split: TrainingSplit) -> WorkoutType {
        switch split {
        case .pushPullLegs,
             .bro,
             .custom:
            .pull // Per Section 18.2: prefer Pull on T+1
        case .upperLower,
             .fullBody:
            .upper
        }
    }

    // Check if date is T-1 (day before a football day)
    // Per MODULE_TRAINING.md Section 18.2

    private func isFootballTMinus1(date: Date, footballDays: ActiveDays) -> Bool {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: date) else {
            return false
        }
        let tomorrowWeekday = cal.component(.weekday, from: tomorrow)
        return footballDays.isActive(on: tomorrowWeekday)
    }

    // Check if date is T+1 (day after a football day)
    // Per MODULE_TRAINING.md Section 18.2

    private func isFootballTPlus1(date: Date, footballDays: ActiveDays) -> Bool {
        let cal = Calendar.current
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: date) else {
            return false
        }
        let yesterdayWeekday = cal.component(.weekday, from: yesterday)
        return footballDays.isActive(on: yesterdayWeekday)
    }
}
