//
// TrainingViewModel+ReadinessSession.swift
// Tempo
//
// Daily readiness session (D2) — assembling today's ReadinessPicture from
// Whoop/HealthKit/calendar/check-in inputs and persisting the DailySession.
// Split out of TrainingViewModel.swift to keep it under the SwiftLint
// file/type-body length caps — same instance methods, hosted in an extension.
//

import Foundation
import SwiftData

extension TrainingViewModel {
    // MARK: - Daily Readiness Session (D2 — the brain + floor)

    /// Once-daily: assemble today's ReadinessPicture from stored history, ask the
    /// DailyReadinessCoach (brain when eligible, deterministic+floor otherwise),
    /// persist the result as a DailySession linked 1:1 to today's WorkoutPlan, and
    /// resolve the plan's state (severe → mark .skipped/.floorForced). The floor
    /// runs on EVERY path (the coach guarantees produce-then-floor). Persisted
    /// once-daily guard caps it at ≤1 Haiku/day.
    /// §11.14 — a schedule edit can reshape TODAY after the coach already
    /// spoke (football day removed → upper, then re-added → football again).
    /// The persisted DailySession then contradicts the plan row — header says
    /// FOOTBALL, card says UPPER — and the day-key guard would hold that
    /// contradiction until midnight. When today's still-PLANNED row no longer
    /// matches the session's modality, drop the stale session and release the
    /// day key so the next coach pass speaks for the day as it now is.
    /// Returns true when a resync is needed. Never touches a decided day
    /// (completed/inProgress/skipped) or an unmappable modality.
    @discardableResult
    func invalidateStaleDailySession(for plan: WorkoutPlan, modelContext: ModelContext) -> Bool {
        guard plan.status == .planned,
              let session = fetchTodayDailySession(modelContext: modelContext),
              let mapped = WorkoutType.fromModality(session.modality),
              mapped != plan.type
        else {
            return false
        }
        modelContext.delete(session)
        dailySession = nil
        let profile = fetchOrCreateAdaptiveProfile(modelContext: modelContext)
        profile.lastDailySessionDayKey = nil
        guard saveGuarded(modelContext, operation: "stale session resync") else { return false }
        #if DEBUG
            print("\(DebugTrace.prefix)[daily_coach] stale session invalidated (session=\(session.modality) plan=\(plan.typeRaw)) — resync")
        #endif
        return true
    }

    /// `deterministicOnly` — COST NOTE (CLAUDE.md AI guardrail): schedule-edit
    /// resyncs re-run the coach for FREE (deterministic candidate only, no
    /// brain call). Only the normal once-daily pass may be brain-eligible.
    func runDailyReadinessSession(modelContext: ModelContext, deterministicOnly: Bool = false) async {
        guard let apiClient else { return }
        guard !sessionState.isActive else { return }
        guard let plan = todayPlan else { return }

        // Once-per-day cap (PERSISTED — survives relaunch, hardens the cost cap).
        let todayKey = AIProgramPlanner.isoDay(Date())
        let profile = fetchOrCreateAdaptiveProfile(modelContext: modelContext)

        #if DEBUG
            // DEBUG test bypass: when set, ignore the once-daily guard so the daily
            // loop can be re-exercised without reinstalling. Clears itself after one
            // run. Set via Settings → Developer → "Force daily coach re-run".
            let forceRerun = UserDefaults.standard.bool(forKey: "tempo.debug.forceDailyRerun")
            if forceRerun {
                UserDefaults.standard.set(false, forKey: "tempo.debug.forceDailyRerun")
                // Delete today's stale session so the fresh one is the only row.
                if let stale = fetchTodayDailySession(modelContext: modelContext) {
                    modelContext.delete(stale)
                }
            }
        #else
            let forceRerun = false
        #endif

        #if DEBUG
            print("\(DebugTrace.prefix)[daily_coach] enter forceRerun=\(forceRerun) alreadyRan=\(profile.lastDailySessionDayKey == todayKey)")
        #endif

        guard forceRerun || profile.lastDailySessionDayKey != todayKey else {
            // Already ran today — surface the persisted session for the card.
            dailySession = fetchTodayDailySession(modelContext: modelContext)
            #if DEBUG
                print("\(DebugTrace.prefix)[daily_coach] guard-skip (cached) — not re-calling today")
            #endif
            return
        }

        // 1. Assemble the picture from stored 30-day history (oldest→newest).
        //    Calendar context (exams ≤7d, today's event load) is fetched here —
        //    the only async input — and handed to the sync assembler.
        let calendarContext = await fetchCalendarContext()
        let picture = assembleTodayPicture(modelContext: modelContext, calendarContext: calendarContext)

        // 2. brainEligible = DATA readiness only (≥30d history AND Whoop fresh).
        //    Entitlement (Pro/consent) is NOT checked here — the coach's 402→
        //    fallback owns that; duplicating risks the two disagreeing.
        //    A §11.14 resync pass is never brain-eligible (free by design).
        let brainEligible = !deterministicOnly
            && picture.hasBaselineForBrain && isWhoopFresh(modelContext: modelContext)

        // 3. Deterministic candidate (cold-start / offline / 402 / parse-fail
        //    fallback) built from the planned modality. Floor still applies to it.
        //    (b)+(c) compose: a two-a-day places its two parts in real calendar
        //    windows (lift in the preferred/free slot, cardio spaced) rather than
        //    a fixed clock; nil → the 08:00/18:00 fallback inside the candidate.
        let secondaryWindows = plan.isTwoADay ? await twoADayWindows(modelContext: modelContext) : nil
        let candidate = deterministicCandidate(for: plan, readiness: picture, secondaryWindows: secondaryWindows)

        // 4. Coach: produce-then-floor.
        let coach = DailyReadinessCoach(apiClient: apiClient)
        let result = await coach.session(
            for: picture,
            plannedModality: plan.type.rawValue,
            deterministicCandidate: candidate,
            brainEligible: brainEligible
        )

        // 5. Persist the DailySession 1:1 (every day — uniform link, §8 revised).
        //    Dedup BEFORE insert — always on, not just the DEBUG force path: a
        //    failed save below leaves today's pending row in the context with
        //    the day-key unconsumed, so the next loadToday re-enters here and
        //    must not stack a second row for the same day.
        if let stale = fetchTodayDailySession(modelContext: modelContext) {
            modelContext.delete(stale)
        }
        let session = DailySession.from(
            decision: result.decision,
            date: Date(),
            source: result.source,
            workoutPlan: plan
        )
        modelContext.insert(session)

        // 6. Resolve the WorkoutPlan state. SEVERE → the planned day is superseded:
        //    mark .skipped with .floorForced so adherence does NOT penalize it
        //    (§8/§15.2 — body said recover, not a user flake).
        if result.decision.tier == .severe {
            plan.status = .skipped
            plan.skipReason = .floorForced
        } else if plan.status == .planned,
                  let mapped = WorkoutType.fromModality(result.decision.session.modality),
                  mapped != plan.type {
            // §8 connect — the brain kept the planned modality unless readiness
            // forced a move; when it DID move (planned pool → prescribed rest at
            // yellow), the plan ROW must follow, or the header/week views keep
            // showing the old day next to a card that says otherwise. The
            // template type is stashed once for the "keep planned workout"
            // override and the planResolution keep-rule.
            if plan.plannedTypeRaw == nil { plan.plannedTypeRaw = plan.typeRaw }
            plan.type = mapped
            // A non-gym day moved TO a gym modality (football → upper: "you've
            // got the headroom, lift") starts with ZERO exercises — without
            // populating here, Start Workout launches a 0/0 session where
            // Finish Set and Skip are both dead. populateExercises no-ops when
            // the plan already has exercises, so this is safe for gym → gym.
            if mapped.isGymWorkout {
                populateExercises(for: plan, modelContext: modelContext)
                snapPrescribedWeights(for: plan, modelContext: modelContext)
            }
            #if DEBUG
                print("\(DebugTrace.prefix)[daily_coach] plan reshaped \(plan.plannedTypeRaw ?? "?") → \(mapped.rawValue) (tier=\(result.decision.tier.rawValue)) exercises=\(plan.orderedExercises.count)")
            #endif
        }

        // Consume the day-key and save ATOMICALLY: key set before the save so
        // success persists both together; on failure the key is REVERTED so
        // the guard at the top doesn't strand the user on a fallback for 24h —
        // the next loadToday re-runs the coach (the dedup above absorbs the
        // pending row, and a duplicate cheap coach call beats a lost day).
        let priorDayKey = profile.lastDailySessionDayKey
        profile.lastDailySessionDayKey = todayKey
        if !saveGuarded(modelContext, operation: "coach session") {
            profile.lastDailySessionDayKey = priorDayKey
        }
        dailySession = session

        #if DEBUG
            print("\(DebugTrace.prefix)[daily_coach] session persisted source=\(result.source.rawValue) tier=\(result.decision.tier.rawValue) modality=\(session.modality) planSkipped=\(result.decision.tier == .severe)")
        #endif
    }

    /// Assemble today's ReadinessPicture from the trailing-30-day DailyRecovery
    /// history (reuses the canonical forward-sorted fetch).
    private func assembleTodayPicture(
        modelContext: ModelContext,
        calendarContext: (exams: [ExamSnapshot], busyHours: Double?) = ([], nil)
    ) -> ReadinessPicture {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let cutoff = cal.date(byAdding: .day, value: -31, to: today) ?? today
        let descriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate { $0.date >= cutoff },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        let snapshots = rows.map { r in
            DailyRecoverySnapshot(
                date: r.date, recoveryScore: r.recoveryScore, hrv: r.hrvRmssd,
                rhr: r.restingHR, respRate: r.respiratoryRate, sleepHours: r.sleepHours,
                sleepDebt: r.sleepDebt, strain: r.strain, deepSleepMin: r.deepSleepMin,
                skinTemp: r.skinTemp, spo2: r.spo2, sleepConsistency: r.sleepConsistency
            )
        }
        let todaySnapshot = snapshots.last(where: { cal.isDate($0.date, inSameDayAs: today) }) ?? snapshots.last

        // Body comp (latest snapshot) + today's check-in surface into the picture.
        let bodyComp = fetchLatestBodyComp(modelContext: modelContext)
        let checkIn = fetchTodayCheckIn(modelContext: modelContext)?.snapshot

        // D3 — days until the next COMPETITIVE match (distinct from recurring
        // football days). Feeds the brain's CONTEXT block + the T-1/T-0 prompt
        // lines, which are about TAPERING for a real game — a friendly scrimmage
        // doesn't drive that, so it's excluded here (matches the T-1 filter in
        // loadWeekPlan and the isCompetitive toggle's promise).
        let competitiveKickoffs = fetchUpcomingMatches(modelContext: modelContext)
            .filter(\.isCompetitive).map(\.kickoff)
        let daysUntilNextMatch = MatchSchedule.daysUntilNextMatch(kickoffs: competitiveKickoffs, from: Date())

        return ReadinessAssembler.assemble(
            history: snapshots,
            today: todaySnapshot,
            yesterdaySessions: fetchYesterdaySessions(modelContext: modelContext),
            yesterdaySessionRPE: fetchYesterdaySessionRPE(modelContext: modelContext),
            bodyComp: bodyComp,
            checkIn: checkIn,
            daysUntilNextMatch: daysUntilNextMatch,
            blockEmphasis: currentBlockEmphasis(modelContext: modelContext),
            venueToday: venueTodaySnapshot(modelContext: modelContext),
            examsSoon: calendarContext.exams,
            busyHoursToday: calendarContext.busyHours
        )
    }

    /// §5 calendar awareness — exams in the next 7 days + today's scheduled
    /// hours. EventKit failures (no auth, no service) read as "no calendar
    /// signal", never an error: the picture just omits the lines.
    private func fetchCalendarContext() async -> (exams: [ExamSnapshot], busyHours: Double?) {
        guard let calendarService else { return ([], nil) }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let weekEnd = cal.date(byAdding: .day, value: 7, to: today),
              let dayEnd = cal.date(byAdding: .day, value: 1, to: today) else { return ([], nil) }

        let exams = calendarService.detectExamDates(in: DateInterval(start: today, end: weekEnd)).map {
            ExamSnapshot(
                subject: $0.subject,
                daysUntil: cal.dateComponents([.day], from: today, to: cal.startOfDay(for: $0.date)).day ?? 0
            )
        }

        let events = (try? await calendarService.fetchEvents(for: DateInterval(start: today, end: dayEnd))) ?? []
        let busyMinutes = events
            .filter { !$0.isAllDay }
            .reduce(0.0) { $0 + max(0, $1.endDate.timeIntervalSince($1.startDate) / 60) }
        return (exams, busyMinutes > 0 ? busyMinutes / 60 : nil)
    }

    /// Yesterday's real activities (Whoop-detected, imported, or attested) —
    /// the §13.2 enrichment: what the body actually DID feeds today's picture.
    private func fetchYesterdaySessions(modelContext: ModelContext) -> [ActivitySnapshot] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else { return [] }
        let descriptor = FetchDescriptor<ActivitySession>(
            predicate: #Predicate { $0.date >= yesterday && $0.date < today }
        )
        return ((try? modelContext.fetch(descriptor)) ?? []).map {
            ActivitySnapshot(
                workoutType: $0.workoutType, strain: $0.strain,
                durationMinutes: $0.durationMinutes, averageHeartRate: $0.averageHeartRate,
                hardMinutes: $0.hardMinutes
            )
        }
    }

    /// §14 #3 — yesterday's one-tap session RPE (the ACTUAL the user reported
    /// on yesterday's completed plan), surfaced into today's picture so the
    /// brain calibrates against felt cost, not just Whoop strain.
    private func fetchYesterdaySessionRPE(modelContext: ModelContext) -> Int? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else { return nil }
        let descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate { $0.date >= yesterday && $0.date < today && $0.sessionRPE != nil }
        )
        return (try? modelContext.fetch(descriptor))?.first?.sessionRPE
    }

    /// Today's venue context for the prompt (§16): the user's confirmed answer
    /// when present (highest quality), else the learned weekday pattern. nil
    /// when neither exists — the prompt stays silent (cold-start honesty).
    private func venueTodaySnapshot(modelContext: ModelContext) -> VenueTodaySnapshot? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)

        let pattern = ((try? modelContext.fetch(FetchDescriptor<VenuePattern>(
            predicate: #Predicate { $0.weekday == weekday }
        ))) ?? []).first

        let confirmation = ((try? modelContext.fetch(FetchDescriptor<VenueConfirmation>(
            predicate: #Predicate { $0.dayKey == today }
        ))) ?? []).first

        if let confirmation {
            return VenueTodaySnapshot(
                venueRaw: confirmation.venueRaw,
                startMin: confirmation.startMin,
                durationMin: pattern?.medianDurationMin,
                confirmed: true,
                assertsTime: true
            )
        }
        guard let pattern, let venueRaw = pattern.venueRaw else { return nil }
        return VenueTodaySnapshot(
            venueRaw: venueRaw,
            startMin: pattern.medianStartMin,
            durationMin: pattern.medianDurationMin,
            confirmed: false,
            assertsTime: pattern.sampleCount >= VenuePatternMath.minSamplesToAssertTime
                && pattern.medianStartMin != nil
        )
    }

    /// The declared training-block emphasis in force today (§14 Decision 1),
    /// or nil when no block covers today — callers default to .physique, the
    /// pre-D3 behavior. Latest-start-wins on overlap (TrainingBlockSchedule).
    func currentBlockEmphasis(modelContext: ModelContext) -> BlockEmphasis? {
        let descriptor = FetchDescriptor<TrainingBlock>()
        let blocks = (try? modelContext.fetch(descriptor)) ?? []
        return TrainingBlockSchedule.currentEmphasis(spans: blocks.map(\.span), on: Date())
    }

    /// Kickoffs of all matches from today forward (start-of-day cutoff so a
    /// match earlier today still counts). Used for the readiness picture's
    /// daysUntilNextMatch and the deterministic week's T-1 leg-protection.
    func fetchUpcomingMatches(modelContext: ModelContext) -> [Match] {
        let cutoff = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<Match>(
            predicate: #Predicate { $0.kickoff >= cutoff },
            sortBy: [SortDescriptor(\.kickoff, order: .forward)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// A minimal deterministic session for the planned modality — the fallback
    /// when the brain is skipped or fails. Gym → pointer (engine fills loads);
    /// non-gym → an easy modality-appropriate block so cold-start/offline never
    /// empty-renders (§15.1/§15.4). The floor still clamps/vetoes this.
    /// §21 (b) + (c) compose — place a two-a-day's two sessions in REAL calendar
    /// windows: the LIFT in the user's preferred/available training window (the
    /// same `suggestWorkoutWindow` that drives the "best window" banner), the
    /// CARDIO spaced ≥6h away on the opposite side of the day. Returns nil — so
    /// the deterministic 08:00/18:00 fallback stands — when there's no calendar,
    /// no free window, or no placement that keeps a valid ≥6h gap in waking hours.
    private func twoADayWindows(modelContext: ModelContext) async -> (liftMin: Int, cardioMin: Int)? {
        guard let calendarService else { return nil }
        let pref = (try? modelContext.fetch(FetchDescriptor<UserDailyPlanProfile>()))?
            .first?.trainingTimePreference ?? .anyFree
        guard let window = await calendarService.suggestWorkoutWindow(for: Date(), preferring: pref) else { return nil }
        let cal = Calendar.current
        let liftMin = cal.component(.hour, from: window.start) * 60 + cal.component(.minute, from: window.start)
        // Space the cardio flush ≥8h from the lift, on the opposite side of the
        // day, clamped to a waking-hours start (06:00–21:00).
        let cardioMin = liftMin < 13 * 60
            ? min(liftMin + 8 * 60, 21 * 60) // morning lift → evening flush
            : max(liftMin - 8 * 60, 6 * 60)  // later lift → morning flush
        guard abs(cardioMin - liftMin) >= 6 * 60 else { return nil } // gap collapsed → fallback
        return (min(liftMin, cardioMin), max(liftMin, cardioMin))    // earliest part first
    }

    func deterministicCandidate(for plan: WorkoutPlan, readiness: ReadinessPicture? = nil,
                                secondaryWindows: (liftMin: Int, cardioMin: Int)? = nil) -> DailySessionDTO {
        let type = plan.type
        let dur = plan.durationMinutes ?? 45
        // Rich-signal ease gate (recovery number + acute:chronic strain + HRV
        // trend, not a bucket). Fires only for the cold-start / offline / 402
        // deterministic path; the brain refines this when eligible, and the
        // safety floor still tiers whatever comes out. nil (no data) = never ease.
        let ease = readiness?.easeCrossTrainingToday ?? false
        let mk: (BlockKind, String?, String) -> SessionBlockDTO = { kind, split, label in
            SessionBlockDTO(kind: kind, label: label, notes: nil, cue: nil, scheduledMin: nil, split: split,
                            reps: nil, distanceM: nil, restSec: nil, intensityPct: nil,
                            durationSec: nil, stroke: nil, runType: nil, paceSecPerKm: nil, sets: nil)
        }
        // An easy recovery swim — the flush a compromised hard cross-training day
        // is stepped down to (conditioning/sprint → pool), and the shape pool days
        // already take. Duration trimmed on an eased day.
        let easySwim: (Int, String) -> DailySessionDTO = { minutes, why in
            DailySessionDTO(
                modality: "pool", intensity: .easy, durationMin: minutes,
                blocks: [SessionBlockDTO(kind: .pool, label: "Easy swim", notes: nil,
                                         cue: "Long strokes, easy pace.", scheduledMin: nil, split: nil,
                                         reps: nil, distanceM: nil, restSec: nil, intensityPct: nil,
                                         durationSec: minutes * 60, stroke: "freestyle", runType: nil,
                                         paceSecPerKm: nil, sets: nil)],
                shortWhy: why, fullWhy: nil, expectedStrain: nil, expectedSessionRPE: 3
            )
        }
        switch type {
        case .push, .pull, .legs, .upper, .lower, .fullBody:
            // §21 two-a-day (requirement (b)) — the week generator marked this GYM
            // day to also carry an easy cardio SECOND session. Emit BOTH as TIMED
            // parts (lift 08:00, cardio 18:00 → a 10h gap that clears the floor's
            // ≥6h composite rule; two untimed blocks would merge into one part, so
            // both must carry a scheduledMin). The Today card then renders two
            // time-separated sections via `.parts`. DROP the second session on a
            // low-readiness morning — the same §2 ease gate that trims cross-
            // training; the safety floor's ACWR/gap rules are the backstop.
            if let second = plan.secondarySessionType, !ease {
                // Timing (requirement (c) composes here): the caller places the
                // lift in the user's REAL calendar/preferred window and spaces the
                // cardio; absent calendar data we fall back to a fixed 08:00/18:00
                // split (still a valid ≥6h gap for the floor).
                let (liftMin, cardioMin) = secondaryWindows ?? (8 * 60, 18 * 60)
                let lift = SessionBlockDTO(
                    kind: .gym, label: type.displayName, notes: nil, cue: nil,
                    scheduledMin: liftMin, split: type.rawValue, reps: nil, distanceM: nil,
                    restSec: nil, intensityPct: nil, durationSec: nil, stroke: nil,
                    runType: nil, paceSecPerKm: nil, sets: nil)
                let isRun = second == .run
                let cardio = SessionBlockDTO(
                    kind: isRun ? .run : .pool,
                    label: isRun ? "Easy run" : "Easy swim", notes: nil,
                    cue: "Easy pace — this is the flush, not extra work.",
                    scheduledMin: cardioMin, split: nil, reps: nil, distanceM: nil,
                    restSec: nil, intensityPct: nil, durationSec: 30 * 60,
                    stroke: isRun ? nil : "freestyle", runType: nil,
                    paceSecPerKm: nil, sets: nil)
                return DailySessionDTO(
                    modality: type.rawValue, intensity: .moderate, durationMin: dur,
                    blocks: [lift, cardio],
                    shortWhy: "Lift, then an easy \(second.displayName.lowercased()) — you've got the headroom today.",
                    fullWhy: nil, expectedStrain: nil, expectedSessionRPE: nil)
            }
            return DailySessionDTO(
                modality: type.rawValue, intensity: .moderate, durationMin: dur,
                blocks: [mk(.gym, type.rawValue, type.displayName)],
                shortWhy: "Today's planned \(type.displayName.lowercased()).", fullWhy: nil,
                expectedStrain: nil, expectedSessionRPE: nil
            )
        case .run:
            // Already easy aerobic; on a compromised day, trim the duration.
            let runDur = ease ? max(20, Int(Double(dur) * 0.7)) : dur
            return DailySessionDTO(
                modality: "run", intensity: .easy, durationMin: runDur,
                blocks: [SessionBlockDTO(kind: .run, label: "Easy run", notes: nil, cue: nil, scheduledMin: nil, split: nil,
                                         reps: nil, distanceM: nil, restSec: nil, intensityPct: nil,
                                         durationSec: runDur * 60, stroke: nil, runType: "tempo",
                                         paceSecPerKm: nil, sets: nil)],
                shortWhy: ease ? "Recovery is down — keep the run short and easy." : "Easy aerobic run.",
                fullWhy: nil, expectedStrain: nil, expectedSessionRPE: 4
            )
        case .sprint, .conditioning:
            // Discretionary HARD cross-training. On a compromised day, swap the
            // modality itself for an easy flush — the floor only clamps intensity,
            // it never does this. Football is a real fixture, handled below.
            if ease {
                return easySwim(max(20, Int(Double(dur) * 0.7)),
                                "Recovery is down — swapped the hard conditioning for an easy flush swim.")
            }
            return DailySessionDTO(
                modality: type.rawValue, intensity: .moderate, durationMin: dur,
                blocks: [mk(.field, nil, type.displayName)],
                shortWhy: "Today's \(type.displayName.lowercased()).", fullWhy: nil,
                expectedStrain: nil, expectedSessionRPE: 5
            )
        case .football:
            // A real fixture — the user shows up regardless; never swapped out.
            return DailySessionDTO(
                modality: type.rawValue, intensity: .moderate, durationMin: dur,
                blocks: [mk(.field, nil, type.displayName)],
                shortWhy: "Today's \(type.displayName.lowercased()).", fullWhy: nil,
                expectedStrain: nil, expectedSessionRPE: 5
            )
        case .pool:
            // Already easy; trim the duration on a compromised day.
            let poolDur = ease ? max(20, Int(Double(dur) * 0.7)) : dur
            return easySwim(poolDur,
                            ease ? "Recovery is down — keep the swim short and easy."
                                 : "Easy recovery swim — flush the legs.")
        case .mobility, .rest:
            return TrainingSafetyFloor.recoverySession(reason: "Recovery day.")
        }
    }

    private func isWhoopFresh(modelContext: ModelContext) -> Bool {
        // Fresh = a DailyRecovery row for today exists (§15.1: >48h stale → no brain).
        loadRecoveryScore(modelContext: modelContext) != nil
    }

    private func fetchTodayDailySession(modelContext: ModelContext) -> DailySession? {
        let today = Calendar.current.startOfDay(for: Date())
        let d = FetchDescriptor<DailySession>(predicate: #Predicate { $0.date == today })
        return try? modelContext.fetch(d).first
    }

    private func fetchLatestBodyComp(modelContext: ModelContext) -> BodyCompSnapshot? {
        var d = FetchDescriptor<BodyComposition>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        d.fetchLimit = 1
        return (try? modelContext.fetch(d))?.first?.snapshot
    }

    private func fetchTodayCheckIn(modelContext: ModelContext) -> MorningCheckIn? {
        let today = Calendar.current.startOfDay(for: Date())
        let d = FetchDescriptor<MorningCheckIn>(predicate: #Predicate { $0.date == today })
        return try? modelContext.fetch(d).first
    }
}
