//
// TrainingViewModel+ExtraGym.swift
// Tempo
//
// "Add gym session" on a soccer day. The day stays ONE WorkoutPlan row: the
// gym part becomes the anchor (type = focus, status = .planned) and the
// already-played football becomes a completed, timed companion. The football
// ActivitySession is never touched (it keeps workoutPlanID == plan.id).
// Decision logic lives in ExtraGymSessionPlanner; this file gathers its inputs
// and applies the result.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    // MARK: - Times

    /// Best guess for when today's soccer started, before the athlete confirms:
    /// today's Match kickoff, then a confirmed venue start time. nil = ask
    /// (the time picker prefills "now"). A Whoop activity's own start time is
    /// applied by `confirmNonGymActivity` and outranks both.
    func suggestedSoccerStart(modelContext: ModelContext) -> Date? {
        let cal = Calendar.current
        if let match = fetchUpcomingMatches(modelContext: modelContext)
            .first(where: { cal.isDateInToday($0.kickoff) })
        {
            return match.kickoff
        }
        let today = cal.startOfDay(for: Date())
        let confirmations = (try? modelContext.fetch(FetchDescriptor<VenueConfirmation>(
            predicate: #Predicate { $0.dayKey == today }
        ))) ?? []
        if let min = confirmations.compactMap(\.startMin).first {
            return cal.date(byAdding: .minute, value: min, to: today)
        }
        return nil
    }

    static func minutesSinceMidnight(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// Default gym time for the sheet: now + 1 h, rounded up to the next 15 min.
    static func defaultGymStartMin(now: Date = Date()) -> Int {
        let raw = minutesSinceMidnight(now) + 60
        return min(23 * 60 + 45, (raw + 14) / 15 * 15)
    }

    // MARK: - Decision inputs

    /// Whether today can take an extra gym session: a football day that is
    /// either still open (it will be logged first) or already logged with
    /// no gym part yet.
    var canAddGymSession: Bool {
        guard let plan = todayPlan else {
            return false
        }
        return plan.type == .football && plan.status != .inProgress && plan.status != .skipped
    }

    /// The soccer facts the planner needs, read from the football
    /// ActivitySession and the plan. `startOverride` is used when football
    /// isn't logged yet (the sheet's soccer time).
    func soccerFacts(startOverride: Date? = nil, modelContext: ModelContext) -> ExtraGymContext.Soccer? {
        guard let plan = todayPlan else {
            return nil
        }
        let planID = plan.id
        let football = WorkoutType.football.rawValue
        let session = (try? modelContext.fetch(FetchDescriptor<ActivitySession>(
            predicate: #Predicate { $0.workoutPlanID == planID && $0.workoutType == football }
        )))?.first
        let cal = Calendar.current
        let startMin: Int
        if let session {
            startMin = Self.minutesSinceMidnight(session.startTime)
        } else if let startOverride {
            startMin = Self.minutesSinceMidnight(startOverride)
        } else if let companion = plan.companionStartMin {
            startMin = companion
        } else {
            return nil
        }
        let isMatch = fetchUpcomingMatches(modelContext: modelContext)
            .contains { cal.isDateInToday($0.kickoff) }
        return .init(
            startMin: startMin,
            durationMin: session?.durationMinutes.map(Int.init) ?? plan.durationMinutes ?? plan.companionDurationMin,
            strain: session?.strain,
            hardMinutes: session?.hardMinutes,
            sessionRPE: plan.sessionRPE ?? plan.companionSessionRPE,
            isMatch: isMatch
        )
    }

    /// Planner context for today. nil when today isn't an eligible football day.
    func extraGymContext(
        gymStartMin: Int,
        soccerStart: Date? = nil,
        requestedFocus: WorkoutType? = nil,
        modelContext: ModelContext
    ) -> ExtraGymContext? {
        guard canAddGymSession,
              let soccer = soccerFacts(startOverride: soccerStart, modelContext: modelContext)
        else {
            return nil
        }
        let cal = Calendar.current
        let tomorrowPlan = tomorrowTemplate(modelContext: modelContext)
        let tomorrowType = tomorrowPlan?.type
        let matchTomorrow = fetchUpcomingMatches(modelContext: modelContext).contains {
            cal.isDateInTomorrow($0.kickoff)
        }
        var done: [WorkoutType] = []
        var remaining: [WorkoutType] = []
        for plan in weekPlans where plan.type.isGymWorkout {
            if plan.date < cal.startOfDay(for: Date()) {
                if plan.status == .completed {
                    done.append(plan.type)
                }
            } else if plan.date > cal.startOfDay(for: Date()) {
                remaining.append(plan.type)
            }
        }
        let cutoff = cal.startOfDay(for: Date())
        let strains = ((try? modelContext.fetch(FetchDescriptor<DailyRecovery>(
            sortBy: [SortDescriptor(\.date, order: .forward)]
        ))) ?? []).filter { $0.date < cutoff }.suffix(30).map(\.strain)
        let score = loadRecoveryScore(modelContext: modelContext)
        return ExtraGymContext(
            soccer: soccer,
            gymStartMin: gymStartMin,
            acwr: ReadinessTrendMath.acuteChronicRatio(strainSeries: Array(strains)),
            recoveryZone: score.map { RecoveryZone(score: $0) },
            floorSevere: dailySession?.floorTier == .severe,
            tomorrowIsMatchOrFootball: matchTomorrow || tomorrowType == .football,
            tomorrowType: tomorrowType,
            weekDoneTypes: done,
            weekRemainingTypes: remaining,
            requestedFocus: requestedFocus
        )
    }

    /// Tomorrow's TEMPLATE plan (transient, never persisted): this week's
    /// entry, or next week's Monday on a Sunday.
    func tomorrowTemplate(modelContext: ModelContext) -> WorkoutPlan? {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) else {
            return nil
        }
        if let match = weekPlans.first(where: { cal.isDate($0.date, inSameDayAs: tomorrow) }) {
            return match
        }
        return previewWeekPlans(
            startingMonday: TrainingCalendar.mondayOfWeek(containing: tomorrow),
            modelContext: modelContext
        ).first { cal.isDate($0.date, inSameDayAs: tomorrow) }
    }

    // MARK: - Add / remove

    /// Turn today's football day into football (done) + a gym session.
    /// Logs the football first (at `soccerStart`) when it isn't logged yet.
    @discardableResult
    func addGymSession(
        decision: ExtraGymDecision,
        gymStartMin: Int,
        soccerStart: Date? = nil,
        modelContext: ModelContext
    ) -> Bool {
        guard let plan = todayPlan, plan.type == .football, plan.companionTypeRaw == nil else {
            return false
        }
        if plan.status != .completed {
            persistNonGymCompletion(whoop: nil, startTime: soccerStart, modelContext: modelContext)
        }
        guard plan.status == .completed else {
            return false
        }

        let planID = plan.id
        let football = WorkoutType.football.rawValue
        let session = (try? modelContext.fetch(FetchDescriptor<ActivitySession>(
            predicate: #Predicate { $0.workoutPlanID == planID && $0.workoutType == football }
        )))?.first

        // Snapshot for a failed-save revert.
        let prior = (
            type: plan.type, status: plan.status, rpe: plan.sessionRPE, finished: plan.finishedAt,
            duration: plan.durationMinutes, recovery: plan.recoveryAdjustment, planned: plan.plannedTypeRaw
        )

        // Football becomes the completed companion.
        plan.companionType = .football
        plan.companionStartMin = session.map { Self.minutesSinceMidnight($0.startTime) }
            ?? soccerStart.map(Self.minutesSinceMidnight)
        plan.companionDurationMin = session?.durationMinutes.map(Int.init) ?? plan.durationMinutes
        plan.companionCompleted = true
        plan.companionSessionRPE = plan.sessionRPE
        plan.companionFinishedAt = plan.finishedAt

        // The gym part is the new anchor.
        plan.sessionRPE = nil
        plan.finishedAt = nil
        plan.durationMinutes = nil
        plan.plannedTypeRaw = nil
        plan.type = decision.focus
        plan.status = .planned
        plan.recoveryAdjustment = decision.loadScale
        plan.scheduledStartMin = gymStartMin
        plan.addedPartIntensityRaw = decision.intensity.rawValue
        plan.addedPartRationale = ([decision.headline] + decision.reasons)
            .map { $0.hasSuffix(".") ? $0 : $0 + "." }
            .joined(separator: " ")

        if decision.focus.isGymWorkout {
            populateExercises(
                for: plan, modelContext: modelContext,
                excludeHeavyLower: decision.excludeHeavyLower
            )
            snapPrescribedWeights(for: plan, modelContext: modelContext)
        }
        // Stops the coach's stale-session resync from turning the day back
        // into football (its modality no longer matches the anchor).
        dailySession?.userOverrode = true

        guard saveGuarded(modelContext, operation: "gym session") else {
            for pe in plan.orderedExercises {
                modelContext.delete(pe)
            }
            plan.exercises = []
            plan.type = prior.type
            plan.status = prior.status
            plan.sessionRPE = prior.rpe
            plan.finishedAt = prior.finished
            plan.durationMinutes = prior.duration
            plan.recoveryAdjustment = prior.recovery
            plan.plannedTypeRaw = prior.planned
            clearCompanion(plan)
            return false
        }
        announceChange(modelContext: modelContext)
        return true
    }

    /// Undo `addGymSession` while the gym part is still untouched.
    @discardableResult
    func removeGymSession(modelContext: ModelContext) -> Bool {
        guard let plan = todayPlan, plan.isCompositeDay, plan.status == .planned,
              hasNoCompletedSets(plan), let companion = plan.companionType
        else {
            return false
        }
        for pe in plan.orderedExercises {
            if let id = pe.exercise?.id {
                deleteUnresolvedPrediction(planID: plan.id, exerciseID: id, modelContext: modelContext)
            }
            modelContext.delete(pe)
        }
        plan.exercises = []
        plan.type = companion
        plan.status = .completed
        plan.sessionRPE = plan.companionSessionRPE
        plan.finishedAt = plan.companionFinishedAt
        plan.durationMinutes = plan.companionDurationMin
        plan.recoveryAdjustment = 1.0
        clearCompanion(plan)
        guard saveGuarded(modelContext, operation: "gym session removal") else {
            return false
        }
        announceChange(modelContext: modelContext)
        return true
    }

    private func clearCompanion(_ plan: WorkoutPlan) {
        plan.companionTypeRaw = nil
        plan.companionStartMin = nil
        plan.companionDurationMin = nil
        plan.companionCompleted = false
        plan.companionSessionRPE = nil
        plan.companionFinishedAt = nil
        plan.scheduledStartMin = nil
        plan.addedPartIntensityRaw = nil
        plan.addedPartRationale = nil
    }

    private func announceChange(modelContext: ModelContext) {
        loadWeekPlan(modelContext: modelContext)
        NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
        NotificationCenter.default.post(
            name: .tempoDayPlanReplanRequested, object: nil,
            userInfo: ["reason": DayPlanReason.workoutLogged.rawValue]
        )
    }
}
