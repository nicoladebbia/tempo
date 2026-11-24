//
// TodayWorkoutView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftData
import SwiftUI
import UserNotifications

// MARK: - Today's Workout View

// Per MODULE_TRAINING.md Section 2 — Launch pad for every training session.
// Per WIREFRAMES.md Section 3 — Training screens.

struct TodayWorkoutView: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Binding
    var showActiveWorkout: Bool
    @Binding
    var showSummary: Bool
    /// The round header buttons (menu, settings), owned by the tab.
    var headerActions: AnyView?
    @Environment(\.modelContext)
    var modelContext
    @Query
    private var allSettings: [UserSettings]
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @State
    private var showMobilityFlows = false
    /// Late-night "Skip for tonight" — persisted (not launch-only): the
    /// timestamp (epoch seconds) until which the bedtime card stays hidden,
    /// today's 05:00 local (`LateNightWindow.skipUntil`). 0 (never skipped
    /// yet, or the persisted value already passed) reads as "not skipped".
    @AppStorage("tempo.latenight.skipUntil")
    private var lateNightSkipUntilRaw: Double = 0
    private var showSessionTonight: Bool {
        Date() < Date(timeIntervalSince1970: lateNightSkipUntilRaw)
    }

    @State
    private var showMonthlyReview = false
    /// Captured at card-tap. The sheet reads THIS, not monthlyReviewDueKey —
    /// generating the summary nils the due key while the sheet is still up,
    /// and the report must not vanish mid-read.
    @State
    private var activeReviewKey: String?
    @Environment(ServiceContainer.self)
    private var services
    /// Suggested free workout window for today (Phase 4). nil = not loaded
    /// or none found.
    @State
    private var suggestedWindow: DateInterval?
    /// A workout event already saved to the calendar for today (future
    /// start). When set, the banner shows a live countdown instead of the
    /// suggestion.
    @State
    private var savedWorkoutEvent: DateInterval?
    @State
    private var showAddToCalendar = false
    /// Drives the once-a-minute countdown refresh.
    @State
    private var now = Date()
    /// Expands the daily session card's full "why" (D2).
    @State
    private var showFullWhy = false
    /// §2.15 — reorder sheet. The styled card stack can't host `.onMove`
    /// (List-only), so reordering lives in a purpose-built List sheet.
    @State
    private var showReorderSheet = false
    /// §2.13 — the exercise slot a long-press picked for swapping. Non-nil
    /// drives the alternatives sheet.
    @State
    private var swapTarget: PlannedExercise?
    /// "This hurts" flow — see PainReportSheet.swift.
    @State
    private var painReportTarget: PlannedExercise?
    /// §2.14 — add-exercise picker sheet.
    @State
    private var showAddExercise = false
    /// My routines — picker sheet and "save as routine" name prompt.
    @State
    private var showRoutines = false
    @State
    private var showSaveRoutine = false
    @State
    private var routineName = ""

    /// Pause/travel-pain feature — refreshed by `.task`/notification below,
    /// same pattern as `MissedTrainerSessionCard`'s own `missed` state.
    @State
    private var activePause: TrainingPause?
    /// A pause must never replace an already-started/completed session.
    private var isTodaySessionSacred: Bool {
        viewModel.todayPlan?.status == .inProgress || viewModel.todayPlan?.status == .completed
    }

    /// Reminder is scheduled at most once per saved-event start.
    private static let workoutReminderID = "tempo.workout.reminder"

    /// Stable identifier of the workout event we saved, plus the day it was
    /// saved for (yyyy-MM-dd). The day-stamp guards against a stale
    /// yesterday-ID binding to today's banner.
    @AppStorage("tempo.workout.eventID")
    private var savedEventID = ""
    @AppStorage("tempo.workout.eventID.day")
    private var savedEventDay = ""

    /// Today's date key for the day-stamp comparison.
    private var todayKey: String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// The persisted event id, but only if it was saved for today.
    private var validEventID: String? {
        guard savedEventDay == todayKey, !savedEventID.isEmpty else {
            return nil
        }
        return savedEventID
    }

    /// Internal (not private) — TodayWorkoutView+TrainerAdjustment.swift reads
    /// this from an extension in a separate file (§4 file-length split).
    var settings: UserSettings? {
        allSettings.first
    }

    /// The date line over the title, from the minute clock this view already keeps.
    private var dateLabel: String {
        now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    /// "Upper day", "Rest day": what today is, in one phrase.
    private var screenTitle: String {
        if activePause != nil, !isTodaySessionSacred {
            return "Paused"
        }
        switch viewModel.todayDisplayState {
        case .gym,
             .nonGym:
            return viewModel.todayPlan.map { $0.type.displayName + " day" } ?? "Train"
        case .restDay:
            return "Rest day"
        case .noPlan:
            return "Train"
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s5) {
                TrainHeader(label: dateLabel, title: screenTitle) {
                    if let headerActions {
                        headerActions
                    }
                }

                // §16 — branch on `todayDisplayState`, not `isRestDay`
                // directly: `isRestDay` reads true for BOTH "no plan yet"
                // and "a real rest day", so checking it first made the
                // empty state below permanently unreachable.
                if viewModel.isLoading {
                    loadingState
                } else if let activePause, !isTodaySessionSacred {
                    // Pause/travel-pain feature — the calm "Paused —
                    // recover" card replaces ALL of Today's normal
                    // content while paused (never a sacred started/
                    // completed session — see `isTodaySessionSacred`).
                    // See PausedTrainingCard.swift.
                    PausedTrainingCard(viewModel: viewModel, pause: activePause)
                } else if showsBedtimeCard(showSessionAnyway: showSessionTonight) {
                    bedtimeCard { lateNightSkipUntilRaw = LateNightWindow.skipUntil().timeIntervalSince1970 }
                } else {
                    switch viewModel.todayDisplayState {
                    case .noPlan:
                        emptyState
                    case .restDay:
                        restDayContent
                    case .gym:
                        if let plan = viewModel.todayPlan {
                            workoutContent(plan: plan)
                        }
                    case .nonGym:
                        // Non-gym training day (football, run, sprint,
                        // conditioning) — no exercises to log, so show a
                        // type-appropriate card instead of empty gym content.
                        if let plan = viewModel.todayPlan {
                            nonGymContent(plan: plan)
                        }
                    }
                }

                // Fix #6 — "Missed <session> — do it today?" (fixed-mode
                // only; renders nothing when there's nothing missed).
                // See MissedTrainerSessionCard.swift.
                if !showsBedtimeCard(showSessionAnyway: showSessionTonight) {
                    // Pause/travel-pain feature — must render even (especially)
                    // while `activePause` is nil, so a fixed-mode pause's
                    // resume decision is never silently skipped. See
                    // WelcomeBackResumeCard.swift.
                    WelcomeBackResumeCard(viewModel: viewModel)

                    MissedTrainerSessionCard(viewModel: viewModel)

                    // Weekly-upload feature — "New week — upload …"
                    // (renders nothing when nothing's due, or the active
                    // program isn't weekly). See WeeklyUploadPromptCard.swift.
                    WeeklyUploadPromptCard(viewModel: viewModel)
                }

                // Suggestions and rituals sit BELOW today's work — the
                // exercise list is what this screen is for.
                // §18.4 — calendar-detected football, confirm-gated.
                // Renders nothing when there's nothing to propose.
                MatchProposalCard()

                // D4 §17 — month-boundary review card, on every day type
                // (the month ends whether today is gym, field, or rest).
                if let dueKey = viewModel.monthlyReviewDueKey {
                    monthlyReviewCard(dueKey)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s6)
        }
        .tidePage(energy: 1)
        .scrollEdgeEffectStyle(.soft, for: .all)
        // §2.16 — pull-to-refresh: full reload through the same coalesced
        // pipeline the .task uses (an in-flight load absorbs the pull).
        .refreshable {
            await viewModel.loadToday(modelContext: modelContext)
        }
        // Start Workout floats over the list — ONLY on a loggable gym day.
        // Non-gym days (rest, mobility, football, run, sprint, conditioning)
        // have nothing to log, so no button is shown.
        .safeAreaBar(edge: .bottom) {
            if viewModel.canStartWorkout, !viewModel.isLoading,
               !showsBedtimeCard(showSessionAnyway: showSessionTonight)
            {
                startWorkoutButton
            }
        }
        .sheet(isPresented: $showReorderSheet) {
            ExerciseReorderSheet(viewModel: viewModel)
                .persistenceAlert()
        }
        .sheet(item: $swapTarget) { target in
            SwapExerciseSheet(viewModel: viewModel, target: target)
        }
        .sheet(item: $painReportTarget) { target in
            PainReportSheet(viewModel: viewModel, plannedExercise: target)
        }
        .sheet(isPresented: $showRoutines) {
            NavigationStack {
                RoutinesView(viewModel: viewModel)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showRoutines = false }
                        }
                    }
            }
            .persistenceAlert()
        }
        .alert("Save as routine", isPresented: $showSaveRoutine) {
            TextField("Name (e.g. Upper A)", text: $routineName)
            Button("Save") {
                viewModel.saveTodayAsRoutine(named: routineName, modelContext: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps these exercises, sets and supersets. Tempo sets the loads each time you run it.")
        }
        .sheet(isPresented: $showAddExercise) {
            AddExerciseSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showMonthlyReview) {
            if let key = activeReviewKey {
                MonthlyReviewView(monthKey: key, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showMobilityFlows) {
            MobilityFlowPickerView(viewModel: viewModel)
        }
        .task {
            await viewModel.loadToday(modelContext: modelContext)
            // §21/§22 — hand the watch today's real queue, and route wrist-
            // logged sets (including ones queued while the app was closed)
            // onto the plan. Registered on the app-level router (not
            // PhoneWatchConnectivityService directly) so every OTHER watch
            // action still reaches its own handler — see WatchActionRouter.
            // Registration replays any buffered actions immediately.
            let watchHandlerViewModel = viewModel
            services.watchActionRouter.setLogSetHandler { [weak watchHandlerViewModel] action in
                guard let viewModel = watchHandlerViewModel else {
                    return false
                }
                return viewModel.applyWatchSetLog(
                    exerciseName: action.payload["exercise"] ?? "",
                    reps: action.payload["reps"].flatMap(Int.init),
                    weightKg: action.payload["weight"].flatMap(Double.init),
                    modelContext: modelContext
                )
            }
            viewModel.pushWorkoutToWatch()
        }
        .task {
            await refreshWorkoutSchedule()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoWorkoutChanged)) { _ in
            // Today's workout was deleted (e.g. from History): reload before
            // anything reads the dead row.
            if viewModel.todayPlan?.isDeleted == true || (viewModel.todayPlan != nil && viewModel.todayPlan?.modelContext == nil) {
                viewModel.todayPlan = nil
                Task { await viewModel.loadToday(modelContext: modelContext) }
                return
            }
            // Any surface that mutates the workout re-syncs the wrist.
            viewModel.pushWorkoutToWatch()
        }
        // Pause/travel-pain feature.
        .task(id: viewModel.todayPlan?.id) {
            refreshActivePause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoTrainingSettingsChanged)) { _ in
            refreshActivePause()
        }
        .task {
            // Once-a-minute countdown refresh (was a Combine Timer.publish
            // tick; replaced to keep this file Combine-free per project
            // convention).
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = Date()
                // Saved event has started — drop the banner.
                if let ev = savedWorkoutEvent, ev.start <= now {
                    savedWorkoutEvent = nil
                }
            }
        }
        .sheet(isPresented: $showAddToCalendar, onDismiss: {
            // Re-read the calendar after the editor closes so a just-saved
            // event flips the banner into countdown mode.
            Task { await refreshWorkoutSchedule() }
        }) {
            if let window = suggestedWindow {
                WorkoutEventEditView(
                    window: window,
                    workoutTitle: viewModel.workoutTypeDisplayName,
                    onSaved: { id in
                        if let id {
                            savedEventID = id
                            savedEventDay = todayKey
                        }
                    }
                )
            }
        }
    }

    // MARK: - Workout Schedule Loading

    /// Pause/travel-pain feature.
    private func refreshActivePause() {
        activePause = viewModel.activePause(modelContext: modelContext)
    }

    /// Loads both the saved workout event (countdown source) and the
    /// suggested free window (fallback). Schedules the 30-min reminder when a
    /// future saved event exists; clears it otherwise.
    private func refreshWorkoutSchedule() async {
        let saved = await services.calendar.todaysWorkoutEvent(
            for: Date(),
            matchingID: validEventID
        )
        savedWorkoutEvent = saved
        if let saved {
            scheduleWorkoutReminder(start: saved.start)
        } else {
            // No event resolved (deleted, past, or none) — clear stale
            // persistence so a dead ID can't shadow a future re-add.
            savedEventID = ""
            savedEventDay = ""
            cancelWorkoutReminder()
            // Requirement (c): bias the suggested slot toward the user's training-
            // time preference (a real free slot inside their preferred daypart,
            // falling back to the largest free gap when that daypart is busy).
            let timePref = (try? modelContext.fetch(FetchDescriptor<UserDailyPlanProfile>()))?
                .first?.trainingTimePreference ?? .anyFree
            suggestedWindow = await services.calendar.suggestWorkoutWindow(for: Date(), preferring: timePref)
        }
    }

    private func scheduleWorkoutReminder(start: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.workoutReminderID])

        let fireDate = start.addingTimeInterval(-30 * 60)
        guard fireDate > Date() else {
            return // less than 30 min away — no point scheduling
        }

        let content = UNMutableNotificationContent()
        content.title = "Gym in 30 min"
        content.body = "Get moving — your workout window is coming up."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.workoutReminderID,
            content: content,
            trigger: trigger
        )
        center.add(request) { _ in }
    }

    private func cancelWorkoutReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.workoutReminderID])
    }

    // MARK: - Workout Content

    private func workoutContent(plan: WorkoutPlan) -> some View {
        // Order: what today IS → what you'll do → the list. Planning banners
        // and suggestions follow the work instead of stacking above it.
        VStack(spacing: Tide.s4) {
            // Workout type header
            workoutHeader(plan: plan)

            // The hero of the day: time, exercises, sets as a lit ring, and
            // how recovery shaped it (the recovery zone + deload line).
            // Per MODULE_TRAINING.md Section 2.5/2.6
            dayHero(plan: plan)

            // D2 — the daily readiness prescription (supersedes the legacy
            // pendingAdjustment card). Modality + intensity + why + blocks/cues.
            if let session = viewModel.dailySession {
                dailySessionCard(session)
            }

            // Benched for recovery/pain: no Start button — an explicit,
            // deliberate way back in instead.
            if viewModel.isRecoveryBenched {
                benchedCard
            }

            // Exercise list
            // Per MODULE_TRAINING.md Section 2.7
            exerciseList(plan: plan)

            // Trainer program: the day's second session (conditioning after
            // the lift), block by block.
            if let second = viewModel.trainerDay(forKey: plan.programSecondaryKey, modelContext: modelContext) {
                trainerSessionCard(second, heading: "Second session", plan: plan, key: plan.programSecondaryKey)
            }

            // §14 #3 — one-tap session RPE, only after completion.
            sessionRPESection(plan: plan)

            // Saved-event countdown takes precedence over the suggestion;
            // both are non-blocking (Phase 4 + follow-up).
            if let saved = savedWorkoutEvent {
                workoutCountdownBanner(saved)
            } else if let window = suggestedWindow {
                workoutWindowBanner(window)
            }

            // §16 — venue propose-confirm (renders only with a learned pattern
            // for today's weekday; collapses once answered or dismissed).
            VenueProposalCard()

            #if DEBUG
                // Force a fresh coach run in-place (no .task / relaunch dependency —
                // the flag + direct call run in one stack). Verifies the daily loop.
                Button("⟳ Run coach now (force, DEBUG)") {
                    UserDefaults.standard.set(true, forKey: "tempo.debug.forceDailyRerun")
                    Task { await viewModel.runDailyReadinessSession(modelContext: modelContext) }
                }
                .font(Tide.caption)
                .foregroundStyle(Color.accentColor)
            #endif
        }
    }

    // MARK: - Workout Header

    @ViewBuilder
    private func workoutHeader(plan: WorkoutPlan) -> some View {
        // The title lives in the screen header. Only while it's still a lifting
        // day — if recovery eased it to rest/mobility, the session card
        // explains; no trainer badge.
        if plan.programSessionKey != nil, plan.type.isGymWorkout {
            Label(plan.notes ?? "Trainer session", systemImage: "person.fill.checkmark")
                .font(Tide.caption)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("From your trainer's program: \(plan.notes ?? "session")")
        }
    }

    // MARK: - Benched (recovery floor / pain)

    private var benchedCard: some View {
        TrainBenchedCard {
            HapticManager.impact(.medium)
            viewModel.trainAnyway(modelContext: modelContext)
        }
    }

    // MARK: - Recovery / Deload Status Line

    // Per MODULE_TRAINING.md Section 2.5 — recovery zone + volume change, and
    // the deload week, as one line inside the session card (was a separate
    // recovery badge + deload banner restating what the card says).

    private func recoveryStatusLine(plan: WorkoutPlan) -> some View {
        // No synced recovery today → say so instead of implying green.
        let hasRecovery = (viewModel.loadRecoveryScore(modelContext: modelContext) ?? 0) > 0
        let dot = Circle()
            .fill(hasRecovery ? recoveryDotColor(plan: plan) : Tide.text3)
            .frame(width: TideTrainSession.dot, height: TideTrainSession.dot)
        let recovery = Text(hasRecovery ? recoveryText(plan: plan) : "No recovery data today")
            .foregroundStyle(Tide.text)
        let adjustment = Text(adjustmentLabel(plan: plan))
            .foregroundStyle(recoveryDotColor(plan: plan))
        let deload = Text("Deload week")
            .fontWeight(.semibold)
            .foregroundStyle(TideTrain.caution)
        return VStack(alignment: .leading, spacing: Tide.hair) {
            // One line when it fits, stacked (never clipped) at big text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tide.s1) {
                    dot
                    recovery
                    Text("·").foregroundStyle(Tide.text3)
                    adjustment
                    if viewModel.isDeloadWeek {
                        Text("·").foregroundStyle(Tide.text3)
                        deload
                    }
                    Spacer(minLength: 0)
                }
                .lineLimit(1)
                VStack(alignment: .leading, spacing: Tide.hair) {
                    HStack(spacing: Tide.s1) {
                        dot
                        recovery
                    }
                    adjustment
                    if viewModel.isDeloadWeek {
                        deload
                    }
                }
            }
            .font(Tide.caption)

            if viewModel.isDeloadWeek {
                Text(viewModel.deloadStyle.blurb)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Daily Session Card (D2 — the readiness prescription)

    @ViewBuilder
    private func dailySessionCard(_ session: DailySession) -> some View {
        if session.userOverrode {
            // §8 connect — he declined the brain's move. One honest line; the
            // plan row (restored) is the day again.
            HStack(spacing: Tide.s2) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(TideTrain.caution)
                    .accessibilityHidden(true)
                Text(
                    "Coach called \(session.modality). You kept \(viewModel.todayPlan?.type.displayName ?? "the plan"). Your call."
                )
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        } else {
            dailySessionCardBody(session)
        }
    }

    private func dailySessionCardBody(_ session: DailySession) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            // What the coach decided, and how hard: the word and a lit bar.
            VStack(alignment: .leading, spacing: Tide.s2) {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                    Text("Today's call").tideLabel()
                    Spacer(minLength: Tide.s2)
                    TrainTag(text: session.intensity.rawValue.capitalized, color: intensityColor(session.intensity))
                }
                Text(session.modality.capitalized)
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
                TideLevelBar(
                    progress: intensityLevel(session.intensity),
                    color: intensityColor(session.intensity),
                    height: Tide.bar
                )
            }
            .accessibilityElement(children: .combine)

            // Floor provenance — honest about how this was produced.
            if session.wasDowngraded || session.source != .brain {
                Text(sessionProvenance(session))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }

            // Short why → tap for full.
            Text(session.shortWhy)
                .font(Tide.body)
                .foregroundStyle(Tide.text2)

            if let full = session.fullWhy, !full.isEmpty {
                if showFullWhy {
                    Text(full)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text3)
                }
                Button(showFullWhy ? "Less" : "Why?") {
                    withAnimation { showFullWhy.toggle() }
                }
                .font(Tide.caption)
                .foregroundStyle(Color.accentColor)
                .frame(minHeight: Tide.hit, alignment: .leading)
                .contentShape(.rect)
            }

            // Blocks (non-gym detail + cues; gym sets render in the exercise
            // list). §21 composite days render grouped by part with a start-time
            // header, and the gym part gets a pointer line so its slot is visible.
            let parts = session.blocks.parts
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if parts.count >= 2 {
                    Text(partHeader(part.scheduledMin))
                        .font(Tide.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(Tide.text3)
                        .padding(.top, Tide.s1)
                }
                ForEach(Array(part.blocks.enumerated()), id: \.offset) { _, block in
                    if block.kind != .gym {
                        blockRow(block)
                    } else if parts.count >= 2 {
                        Text("Gym \(block.split.map { "(\($0))" } ?? "") — exercises below")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                }
            }

            // §21 (b) two-a-day — the cardio SECOND session is a bonus tracked
            // apart from the lift (the day counts as trained on the lift itself),
            // so it gets its own check-off. Gate on TODAY'S actual prescription
            // (parts >= 2) — not just the plan-level flag: a low-readiness morning
            // DROPS the second part from the prescription, and offering to "mark
            // done" a session that readiness prescribed away would contradict the
            // card above. When kept, the plan-level flag is what completion writes.
            if session.blocks.parts.count >= 2,
               let plan = viewModel.todayPlan,
               plan.isTwoADay,
               let second = plan.secondarySessionType
            {
                TrainSessionRule()
                HStack(spacing: Tide.s2) {
                    Image(systemName: plan.secondaryCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(plan.secondaryCompleted ? Color.accentColor : Tide.text3)
                    Text("\(second.displayName) — second session")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .strikethrough(plan.secondaryCompleted, color: Tide.text3)
                    Spacer()
                    Button(plan.secondaryCompleted ? "Undo" : "Mark done") {
                        HapticManager.selection()
                        viewModel.toggleSecondarySessionComplete(modelContext: modelContext)
                    }
                    .font(Tide.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)
                    .frame(minHeight: Tide.hit)
                    .contentShape(.rect)
                }
            }

            // §8 connect — the brain moved the day off the planned modality.
            // Say so, and hand him the override. Brain-chosen moves only: a
            // SEVERE floor skip never stashes plannedTypeRaw, so this row
            // can't appear on a locked recovery day.
            if let plan = viewModel.todayPlan,
               plan.status == .planned,
               let plannedRaw = plan.plannedTypeRaw,
               let plannedType = WorkoutType(rawValue: plannedRaw)
            {
                TrainSessionRule()
                HStack {
                    Text("Plan said \(plannedType.displayName).")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                    Spacer()
                    Button("Keep \(plannedType.displayName)") {
                        HapticManager.selection()
                        viewModel.keepPlannedWorkout(modelContext: modelContext)
                    }
                    .font(Tide.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.accentColor)
                    .frame(minHeight: Tide.hit)
                    .contentShape(.rect)
                }
            }
        }
        .tideCard(padding: Tide.s4)
    }

    /// §21 — part header for a composite day ("AT 16:00" / "ANYTIME" for the
    /// untimed anchor).
    private func partHeader(_ scheduledMin: Int?) -> String {
        scheduledMin.map { "At \(VenuePatternMath.clockLabel($0))" } ?? "Anytime"
    }

    private func blockRow(_ block: SessionBlockDTO) -> some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            Text(block.label)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
            if let cue = block.cue, !cue.isEmpty {
                Text(cue)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Tide.s1)
    }

    private func intensityColor(_ intensity: SessionIntensity) -> Color {
        switch intensity {
        case .recovery,
             .easy: TideTrain.positive
        case .moderate: TideTrain.caution
        case .hard,
             .max: Tide.danger
        }
    }

    /// How full the intensity bar is: recovery at the bottom, max at the top.
    private func intensityLevel(_ intensity: SessionIntensity) -> Double {
        switch intensity {
        case .recovery: 0.2
        case .easy: 0.4
        case .moderate: 0.6
        case .hard: 0.8
        case .max: 1.0
        }
    }

    private func sessionProvenance(_ session: DailySession) -> String {
        if session.wasDowngraded {
            return "Adjusted for recovery — body data wins."
        }
        switch session.source {
        case .floorFallback: return "Using your planned session (AI unavailable right now)."
        case .simple: return "Building your baseline — recovery-aware, trends still warming up."
        case .brain: return ""
        }
    }

    // MARK: - Workout Window Banner

    // Per build done_when #16 — non-blocking suggestion banner.

    private func workoutWindowBanner(_ window: DateInterval) -> some View {
        TrainWindowCard(start: window.start, end: window.end) {
            showAddToCalendar = true
            HapticManager.selection()
        }
    }

    // MARK: - Workout Countdown Banner

    // Shown once an event is saved to the calendar: live "Gym in Xh Ym"
    // counting down to the saved start, refreshed each minute by the
    // once-a-minute countdown `.task`. Clears itself when the start passes.

    private func workoutCountdownBanner(_ event: DateInterval) -> some View {
        TrainCountdownCard(title: "Gym in \(countdownString(to: event.start)) — \(timeString(event.start))")
    }

    /// "3h 32m" / "47m" / "soon" — derived from `now` so it re-renders on
    /// each once-a-minute countdown tick.
    private func countdownString(to start: Date) -> String {
        let remaining = Int(start.timeIntervalSince(now))
        guard remaining > 0 else {
            return "soon"
        }
        let hours = remaining / 3600
        let minutes = (remaining % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(minutes, 1))m"
    }

    private func timeString(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    // MARK: - Day Hero

    // Per MODULE_TRAINING.md Section 2.6 — what today is, as one figure: the
    // time, the exercises, the sets as a lit ring, and how recovery shaped it.

    private func dayHero(plan: WorkoutPlan) -> some View {
        // Done day: the real duration, and what was actually done vs
        // planned — not the plan's estimate ("~0 min · 6 exercises").
        let isDone = plan.status == .completed
        let total = plan.orderedExercises.count
        let minutes = isDone ? max(1, plan.durationMinutes ?? 0) : (plan.durationMinutes ?? estimatedDuration(plan: plan))
        var muscles: [String] = []
        for planned in plan.orderedExercises {
            if let name = planned.exercise?.muscleGroup.displayName, !muscles.contains(name) {
                muscles.append(name)
            }
        }
        return TrainDayHero(
            label: isDone ? "Time" : "Estimated time",
            figure: "\(minutes)",
            unit: "min",
            stats: [.init(value: isDone ? "\(plan.performedExerciseCount)/\(total)" : "\(total)", label: "exercises")],
            chips: Array(muscles.prefix(4))
        ) {
            TrainSetsRing(done: plan.completedSets, total: plan.totalSets, tint: isDone ? TideTrain.positive : nil)
        } footer: {
            recoveryStatusLine(plan: plan)
        }
    }

    /// "Exercises" over the list, with the reorder entry point (§2.15) at its
    /// end. Planned days only: mid-session reordering would fight
    /// currentExerciseIndex, and a completed day's order is history.
    private func exercisesHeader(plan: WorkoutPlan) -> some View {
        let showsReorder = plan.status == .planned && plan.orderedExercises.count > 1
        return HStack(alignment: .center, spacing: Tide.s2) {
            Text("Exercises")
                .tideLabel()
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Tide.s2)
            if showsReorder {
                Button {
                    showReorderSheet = true
                    HapticManager.selection()
                } label: {
                    Label("Reorder", systemImage: "arrow.up.arrow.down")
                        .font(Tide.caption)
                        .foregroundStyle(TideTrain.caution)
                        .frame(minHeight: Tide.hit)
                        .contentShape(.rect)
                }
            }
        }
        .padding(.horizontal, Tide.s1)
    }

    // MARK: - Monthly Review Card (D4 §17 — the month-boundary ritual)

    private func monthlyReviewCard(_ monthKey: String) -> some View {
        TrainMonthlyReviewCard {
            activeReviewKey = monthKey
            showMonthlyReview = true
        }
    }

    // MARK: - Session RPE Capsule (§14 #3 — one-tap felt cost, post-completion)

    /// Renders ONLY when today's plan is completed: a one-tap 1–10 rating while
    /// unanswered, a quiet confirmation row once logged. The answer is the
    /// ACTUAL paired against the brain's expectedSessionRPE (accuracy spine)
    /// and is surfaced in tomorrow's prompt.
    @ViewBuilder
    private func sessionRPESection(plan: WorkoutPlan) -> some View {
        if plan.status == .completed {
            TrainRPECard(logged: plan.sessionRPE) { value in
                viewModel.recordSessionRPE(value, modelContext: modelContext)
            }
        }
    }

    // MARK: - Exercise List

    // Per MODULE_TRAINING.md Section 2.7 — one card, one row per exercise
    // (picture, name, prescription), so the whole session reads at a glance.
    // Supersets and circuits share a rail.

    private func exerciseList(plan: WorkoutPlan) -> some View {
        let exercises = plan.orderedExercises
        let groups = groupedBySupersets(exercises)

        return VStack(alignment: .leading, spacing: Tide.s2) {
            exercisesHeader(plan: plan)

            TrainListCard {
                ForEach(Array(groups.enumerated()), id: \.offset) { position, group in
                    if position > 0 {
                        TrainPlanDivider()
                    }
                    if group.count > 1 {
                        // Superset/circuit group: shared rail with connecting indicator
                        supersetCard(
                            exercises: group,
                            startIndex: exercises.firstIndex(where: { $0.id == group[0].id }) ?? 0,
                            allExercises: exercises
                        )
                    } else if let single = group.first {
                        let idx = (exercises.firstIndex(where: { $0.id == single.id }) ?? 0)
                        exerciseCard(index: idx + 1, plannedExercise: single, allExercises: exercises)
                    }
                }
            }

            // §2.14 — add-exercise entry point (wireframe Screen 11).
            if plan.status == .planned || plan.status == .inProgress {
                addExerciseButton
                    .padding(.top, Tide.s2)
            }

            // My routines — run your own program today, or keep this one.
            if plan.status == .planned {
                routineButtons
            }
        }
    }

    private var routineButtons: some View {
        let use = Button {
            showRoutines = true
        } label: {
            Label("Use a routine", systemImage: "list.bullet.rectangle")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tideGlass)
        let save = Button {
            routineName = ""
            showSaveRoutine = true
        } label: {
            Label("Save as routine", systemImage: "square.and.arrow.down")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tideGlass)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s2) {
                use
                save
            }
            VStack(spacing: Tide.s2) {
                use
                save
            }
        }
    }

    private var addExerciseButton: some View {
        TrainPlanAddButton(title: "Add exercise") {
            showAddExercise = true
        }
    }

    /// §2.13 — a slot can swap while nothing on it is logged yet; completed
    /// sets pin the movement (logged work is never re-attributed).
    private func canSwap(_ plannedExercise: PlannedExercise) -> Bool {
        let status = plannedExercise.workoutPlan?.status
        guard status == .planned || status == .inProgress else {
            return false
        }
        return plannedExercise.orderedSets.allSatisfy { !$0.completed }
    }

    /// Groups exercises by supersetGroup. Consecutive exercises with the same non-nil supersetGroup
    /// are grouped together; exercises without a superset group are returned as single-element arrays.
    private func groupedBySupersets(_ exercises: [PlannedExercise]) -> [[PlannedExercise]] {
        var groups: [[PlannedExercise]] = []
        var current: [PlannedExercise] = []
        var currentGroup: Int? = nil

        for ex in exercises {
            if let sg = ex.supersetGroup {
                if sg == currentGroup {
                    current.append(ex)
                } else {
                    if !current.isEmpty {
                        groups.append(current)
                    }
                    current = [ex]
                    currentGroup = sg
                }
            } else {
                if !current.isEmpty {
                    groups.append(current)
                }
                current = []
                currentGroup = nil
                groups.append([ex])
            }
        }
        if !current.isEmpty {
            groups.append(current)
        }
        return groups
    }

    private func supersetCard(exercises: [PlannedExercise], startIndex: Int, allExercises: [PlannedExercise]) -> some View {
        // §6.3 — a group of 2 is a superset, 3+ is a circuit. Same shared
        // block either way; only the badge word changes.
        let isCircuit = exercises.count > 2
        return VStack(alignment: .leading, spacing: 0) {
            // Superset/circuit header badge
            HStack(spacing: Tide.hair) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(Tide.label)
                    .accessibilityHidden(true)
                Text(isCircuit ? "Circuit" : "Superset")
                    .font(Tide.bodyStrong)
            }
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, Tide.s4)
            .padding(.top, Tide.s3)

            // The rows, joined by a rail in the accent.
            HStack(alignment: .top, spacing: 0) {
                Capsule()
                    .fill(Color.accentColor.opacity(TideTrainSession.outlineOpacity))
                    .frame(width: TideTrain.groupRail)
                    .padding(.leading, Tide.s4)
                    .padding(.vertical, Tide.s2)
                VStack(spacing: 0) {
                    ForEach(Array(exercises.enumerated()), id: \.element.id) { idx, plannedEx in
                        if idx > 0 {
                            TrainPlanDivider()
                                .padding(.horizontal, Tide.s4)
                        }
                        exerciseCard(index: startIndex + idx + 1, plannedExercise: plannedEx, allExercises: allExercises)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(TideTrainSession.zoneBandOpacity / 2))
    }

    private func exerciseCard(index: Int, plannedExercise: PlannedExercise, allExercises: [PlannedExercise]) -> some View {
        Group {
            if let exercise = plannedExercise.exercise {
                NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                    exerciseCardRow(exercise: exercise, index: index, plannedExercise: plannedExercise)
                }
                .buttonStyle(.trainRow)
            } else {
                exerciseCardRow(exercise: nil, index: index, plannedExercise: plannedExercise)
            }
        }
        // §2.13 — long-press swap (TESTING_STRATEGY UT-005 / M-T-008).
        // §6.5 — long-press group control: manually group with the next
        // exercise (grows a superset into a circuit) or break out of the
        // current group. Auto-assignment still runs by default; this is the
        // manual override.
        .contextMenu {
            if canSwap(plannedExercise) {
                Button {
                    swapTarget = plannedExercise
                } label: {
                    Label("Swap Exercise", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            if canSwap(plannedExercise), let next = nextExercise(after: plannedExercise, in: allExercises), canSwap(next),
               plannedExercise.supersetGroup == nil || plannedExercise.supersetGroup != next.supersetGroup
            {
                Button {
                    viewModel.groupWithNext(plannedExercise, modelContext: modelContext)
                } label: {
                    Label("Group with Next", systemImage: "link")
                }
            }
            if canSwap(plannedExercise), plannedExercise.supersetGroup != nil {
                Button(role: .destructive) {
                    viewModel.breakGroup(plannedExercise, modelContext: modelContext)
                } label: {
                    Label("Break Group", systemImage: "link.badge.minus")
                }
            }
            // "This hurts" flow — see PainReportSheet.swift.
            Button {
                painReportTarget = plannedExercise
            } label: {
                Label("This hurts", systemImage: "bandage.fill")
            }
        }
    }

    /// The exercise immediately after `plannedExercise` in plan order, or nil
    /// at the end of the list. Used only by the manual group-control menu.
    private func nextExercise(after plannedExercise: PlannedExercise, in allExercises: [PlannedExercise]) -> PlannedExercise? {
        guard let idx = allExercises.firstIndex(where: { $0.id == plannedExercise.id }),
              idx + 1 < allExercises.count
        else {
            return nil
        }
        return allExercises[idx + 1]
    }

    /// The text of one exercise row (the picture and the number sit beside it,
    /// see TodayWorkoutView+Thumbnail.swift). Not private: that extension, in a
    /// separate file, calls this to keep this already-near-the-cap file from
    /// growing further — same convention as TodayWorkoutView+Equipment.swift.
    func exerciseCardContent(plannedExercise: PlannedExercise) -> some View {
        VStack(alignment: .leading, spacing: Tide.s1) {
            // Line 1: name + pain caution + chevron
            HStack(alignment: .firstTextBaseline, spacing: Tide.s2) {
                Text(plannedExercise.exercise?.name ?? "Exercise")
                    .accessibilityLabel((plannedExercise.exercise?.name ?? "Exercise").uppercased())
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: Tide.s2)

                // "This hurts" flow — caution chip while a pain report on this
                // exercise is still inside its 7-day window. See PainReport.swift.
                if let exerciseID = plannedExercise.exercise?.id,
                   viewModel.recentPainCaution(for: exerciseID, modelContext: modelContext) != nil
                {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Tide.label)
                        .foregroundStyle(TideTrain.caution)
                        .accessibilityLabel("Recent pain reported on this exercise")
                }

                Image(systemName: "chevron.right")
                    .font(Tide.label)
                    .foregroundStyle(Tide.text3)
                    .accessibilityHidden(true)
            }

            // Line 2: Sets x Reps @ Weight, in figures.
            // §5 fix — `.orderedSets` (setNumber-sorted), NOT the raw `.sets`
            // relationship array: SwiftData doesn't guarantee that array's
            // order matches setNumber, and prescriptionText's "first working
            // set" must be the ACTUAL first (the calibration set, when this
            // exercise has one) — an arbitrary working set showing "(BW)"
            // instead of the calibration copy is exactly this bug.
            let orderedSets = plannedExercise.orderedSets
            if let firstSet = orderedSets.first {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                    Text(prescriptionText(
                        sets: orderedSets, firstSet: firstSet,
                        isTrainerDay: plannedExercise.workoutPlan?.programSessionKey != nil, perSide: plannedExercise.perSide
                    ))
                    .font(TideTrain.figure(.subheadline, weight: .medium))
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)

                    // Progressive overload indicator
                    if let notes = plannedExercise.workoutPlan?.notes,
                       notes.contains("Increased")
                    {
                        Image(systemName: "arrow.up.right")
                            .font(Tide.label)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }

            // Once the session has started, one tick per working set.
            if plannedExercise.workoutPlan?.status != .planned {
                let working = plannedExercise.orderedSets.filter { !$0.isWarmup }
                if !working.isEmpty {
                    TrainSetTicks(done: working.filter(\.completed).count, total: working.count)
                        .padding(.vertical, Tide.hair)
                }
            }

            // Line 3: intensity zone, muscle group and equipment. §11.12 — the
            // zone (HEAVY/BUILD/PUMP) is recovered from the rep target; only
            // e1RM-anchored prescriptions carry RIR, so gate on that to avoid
            // mislabeling legacy 8/12 fallbacks.
            let metaParts = [
                plannedExercise.exercise?.muscleGroup.displayName,
                plannedExercise.exercise.map { equipmentHint($0.equipment) },
            ].compactMap(\.self)
            HStack(spacing: Tide.s2) {
                if let firstWorking = plannedExercise.orderedSets.first(where: { !$0.isWarmup }),
                   firstWorking.targetRIR != nil
                {
                    let zone = PrescriptionMath.zoneLabel(forReps: firstWorking.targetReps)
                    TrainTag(text: zone.capitalized, color: zone == "HEAVY" ? Color.accentColor : TideTrain.caution)
                }
                if !metaParts.isEmpty {
                    Text(metaParts.joined(separator: " · "))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                        .lineLimit(1)
                }
            }

            // Travel/hotel-gym swap label — see TravelSwapEngine.swift.
            if let original = plannedExercise.travelSwapOriginalName {
                Label("Hotel swap for \(original)", systemImage: "arrow.triangle.2.circlepath")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.water)
            }

            // "This hurts" flow — skipped-for-pain marker.
            if let painLabel = plannedExercise.painStatusLabel {
                Label(painLabel, systemImage: "bandage.fill")
                    .font(Tide.caption)
                    .foregroundStyle(TideTrain.caution)
            }

            // Trainer program: their cue / rest for this exercise.
            if plannedExercise.programNote != nil || plannedExercise.restSecondsOverride != nil {
                Text([
                    plannedExercise.programNote,
                    plannedExercise.restSecondsOverride.map { "Rest \($0)s" },
                ].compactMap(\.self).joined(separator: " · "))
                    .font(Tide.caption)
                    .foregroundStyle(Color.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // §4 — the trainer's own target when Tempo adjusted it (recovery
            // multiplier / pain-note cap), plus a one-tap way to use theirs
            // instead for the sets still to come today.
            trainerAdjustmentRow(plannedExercise)

            // Line 4: Last 3 sessions' performance with trend indicator
            if let exercise = plannedExercise.exercise {
                let recentSessions = lastThreePerformances(for: exercise)
                if !recentSessions.isEmpty {
                    let trend = performanceTrend(sessions: recentSessions)
                    HStack(spacing: Tide.s1) {
                        Text("Recent")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                        Text(trend.symbol)
                            .font(TideTrain.figure(.caption, weight: .bold))
                            .foregroundStyle(trend.color)
                        ForEach(Array(recentSessions.enumerated()), id: \.offset) { idx, session in
                            Text(bestSetSummary(history: session))
                                .font(TideTrain.figure(.caption))
                                .foregroundStyle(idx == 0 ? Tide.text2 : Tide.text3)
                                .lineLimit(1)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(Tide.labelShrink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // trainerAdjustmentRow (§4) moved to TodayWorkoutView+TrainerAdjustment.swift
    // to keep this file under the SwiftLint file/type-body length caps.

    // MARK: - Start Workout Button

    // Per MODULE_TRAINING.md Section 2.9

    private var startWorkoutButton: some View {
        Button {
            HapticManager.impact(.heavy)
            if viewModel.startWorkout() {
                showActiveWorkout = true
            }
        } label: {
            Label("Start workout", systemImage: "play.fill")
        }
        .buttonStyle(.tidePrimary)
        // UI tests (and VoiceOver users of the old build) know this button by
        // its old name.
        .accessibilityLabel("START WORKOUT")
        .padding(.horizontal, Tide.edge)
        .padding(.bottom, Tide.s2)
    }

    // MARK: - Rest Day Content

    // Per MODULE_TRAINING.md Section 2.10

    private var restDayContent: some View {
        VStack(spacing: Tide.s4) {
            // §8 connect — a brain-reshaped rest day (planned pool → rest)
            // renders THIS content, so the prescription's why + the "keep
            // planned workout" override must live here too, not just on
            // gym/non-gym days.
            if let session = viewModel.dailySession {
                dailySessionCard(session)
            }

            TrainDayCard(
                label: "Rest day",
                symbol: "figure.yoga",
                tint: TideTrain.positive,
                title: "Your body builds muscle while you rest.",
                tomorrow: nextWorkoutType
            ) {
                // Mobility flow button
                mobilityFlowButton
            }
        }
        .padding(.top, Tide.s3)
    }

    private var mobilityFlowButton: some View {
        Button {
            showMobilityFlows = true
        } label: {
            Label("Start a mobility flow", systemImage: "figure.flexibility")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tideGlass)
    }

    // MARK: - Non-Gym Training Day Content

    /// Shown for training days that aren't loggable gym sessions — football,
    /// run, sprint, conditioning. These have no exercises/sets to log, so there
    /// is no "Start Workout" button; this card just tells the user what today is.
    private func nonGymContent(plan: WorkoutPlan) -> some View {
        // §11.7 — compact: one screen, no dead air. The day first (what it is
        // and what tomorrow is), then what to do, then the way to log it.
        VStack(spacing: Tide.s4) {
            TrainDayCard(
                label: "Today",
                symbol: nonGymIcon(for: plan.type),
                title: plan.type.displayName,
                message: nonGymMessage(for: plan.type),
                tomorrow: nextWorkoutType
            ) {}

            // Trainer program: the coach's own conditioning session, block by block.
            let trainerDay = viewModel.trainerDay(forKey: plan.programSessionKey, modelContext: modelContext)
            if let trainerDay {
                trainerSessionCard(trainerDay, heading: "Your trainer's session", plan: plan, key: plan.programSessionKey)
            }

            // §16 — venue propose-confirm, same placement as the gym path.
            VenueProposalCard()

            // D2 — the readiness prescription IS the content on a non-gym day
            // (modality/intensity/why + blocks with cues; there's no exercise list).
            // A trainer's session IS the prescription — Tempo's generic card
            // ("Today's conditioning.") on top of it only confused the day.
            if trainerDay == nil, let session = viewModel.dailySession {
                dailySessionCard(session)
            }

            // §10 — a mobility DAY gets the guided flows as its session (the
            // flow's completion marks the day done through the non-gym path).
            if plan.type == .mobility, plan.status != .completed {
                mobilityFlowButton
            }

            // The actual cross-training prescription (what to DO), so a cardio
            // day isn't just an icon + one line. Reads type + duration off the
            // plan. FALLBACK ONLY: when the daily brain already produced a
            // DailySession card above, defer to it — don't show two prescriptions.
            if trainerDay == nil, viewModel.dailySession == nil, let rx = cardioPrescription(for: plan) {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    Text("Today's prescription").tideLabel()
                    Text(rx.headline)
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(rx.detail)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tideCard(padding: Tide.s4)
            }

            // Whoop activity confirm / saved summary. With a trainer session
            // the guided run / per-block Log already completes the day, so
            // the bare manual button is left out (a found Whoop activity
            // still asks to confirm).
            nonGymActivitySection(plan: plan, hasTrainerSession: trainerDay != nil)

            // §13 — running days link to the run history (HealthKit-mirrored
            // distance/pace/splits).
            if plan.type == .run || plan.type == .sprint || plan.type == .conditioning {
                NavigationLink(destination: RunHistoryView()) {
                    Label("Past runs", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tideGlass)
            }

            // §14 #3 — one-tap session RPE, only after completion.
            sessionRPESection(plan: plan)
        }
        .task(id: plan.id) {
            await viewModel.loadNonGymActivity(modelContext: modelContext)
        }
    }

    /// The strain/HR confirm-and-save block beneath the non-gym card.
    @ViewBuilder
    private func nonGymActivitySection(plan: WorkoutPlan, hasTrainerSession: Bool) -> some View {
        switch viewModel.nonGymActivityState {
        case .loading:
            HStack(spacing: Tide.s3) {
                ProgressView()
                Text("Checking for today's activity")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text2)
                Spacer(minLength: 0)
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)

        case let .foundTagged(summary):
            VStack(spacing: Tide.s3) {
                activityStatsRow(summary)
                confirmButton(
                    title: "Confirm — that was \(plan.type.displayName.lowercased())",
                    summary: summary
                )
            }

        case let .foundUntagged(summary):
            VStack(spacing: Tide.s2) {
                activityStatsRow(summary)
                Text("Found an activity today — was this \(plan.type.displayName.lowercased())?")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Tide.s2)
                confirmButton(title: "Yes, log it", summary: summary)
                Button {
                    HapticManager.impact(.light)
                    viewModel.dismissNonGymActivity()
                } label: {
                    Text("No — that wasn't \(plan.type.displayName.lowercased())")
                }
                .buttonStyle(.trainQuiet)
            }

        case .none,
             .dismissed:
            if !hasTrainerSession {
                confirmButton(
                    title: plan.type == .football ? "Log that I played" : "Mark \(plan.type.displayName.lowercased()) done",
                    summary: nil
                )
            }

        case let .saved(summary):
            VStack(spacing: Tide.s3) {
                HStack(spacing: Tide.s2) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(TideTrain.positive)
                    Text("Logged")
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                }
                .frame(maxWidth: .infinity, minHeight: Tide.fieldHeight)
                .background(TideTrain.positive.opacity(TideTrainSession.zoneBandOpacity), in: .capsule)
                .accessibilityElement(children: .combine)
                if let summary {
                    activityStatsRow(summary)
                }
            }
        }
    }

    /// Strain, time, heart rate and calories from the found activity, in one card.
    private func activityStatsRow(_ s: TrainingViewModel.WhoopActivitySummary) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: Tide.s3, alignment: .leading),
                    count: typeSize.isAccessibilitySize ? 1 : 4
                ),
                alignment: .leading,
                spacing: Tide.s3
            ) {
                activityStat(value: String(format: "%.1f", s.strain), label: "Strain")
                activityStat(value: "\(Int(s.durationMinutes))", unit: "min", label: "Duration")
                activityStat(value: "\(Int(s.averageHeartRate))", unit: "bpm", label: "Avg HR")
                activityStat(value: "\(Int(s.caloriesBurned))", unit: "kcal", label: "Cal")
            }
            sweatHydrationNote(s)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    /// Estimated sweat loss + hydration guidance from the same HydrationMath
    /// the daily target uses. Shown as a range (rough estimate), with an
    /// electrolyte nudge for larger losses.
    @ViewBuilder
    private func sweatHydrationNote(_ s: TrainingViewModel.WhoopActivitySummary) -> some View {
        if let range = HydrationMath.sweatLossLitres(
            caloriesBurned: s.caloriesBurned,
            durationMinutes: s.durationMinutes
        ) {
            let needsElectrolytes = HydrationMath.needsElectrolytes(range.lowerBound)
            VStack(alignment: .leading, spacing: Tide.hair) {
                HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
                    Image(systemName: "drop.fill")
                        .font(Tide.label)
                        .foregroundStyle(Tide.water)
                    Text(String(format: "~%.1f–%.1f L lost — drink to replace", range.lowerBound, range.upperBound))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if needsElectrolytes {
                    Text("Add electrolytes, not just water.")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text3)
                }
            }
        }
    }

    private func activityStat(value: String, unit: String? = nil, label: String) -> some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            TideNumber(value, unit: unit, size: Tide.numeralS, relativeTo: .title3)
            Text(label)
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
        }
        .accessibilityElement(children: .combine)
    }

    private func confirmButton(
        title: String,
        summary: TrainingViewModel.WhoopActivitySummary?
    ) -> some View {
        Button {
            HapticManager.notification(.success)
            viewModel.confirmNonGymActivity(summary, modelContext: modelContext)
        } label: {
            Text(title)
        }
        .buttonStyle(.tidePrimary)
    }

    /// Fix #7 — shared by both TrainerSessionCard call sites (main session +
    /// two-a-day second session) so each stays a one-line call.
    private func trainerSessionCard(_ day: ProgramDay, heading: String, plan: WorkoutPlan, key: String?) -> some View {
        let isSecondary = key != nil && key == plan.programSecondaryKey
        let isDone = isSecondary ? plan.secondaryCompleted : plan.status == .completed
        return TrainerSessionCard(
            day: day, heading: heading, workoutPlanID: plan.id, programSessionKey: key, viewModel: viewModel, isDone: isDone
        )
    }

    private func nonGymIcon(for type: WorkoutType) -> String {
        switch type {
        case .football: "sportscourt.fill"
        case .run: "figure.run"
        case .sprint: "figure.run.treadmill"
        case .conditioning: "bolt.heart.fill"
        case .pool: "figure.pool.swim"
        case .mobility: "figure.cooldown"
        default: "figure.mixed.cardio"
        }
    }

    private func nonGymMessage(for type: WorkoutType) -> String {
        switch type {
        case .football: "Football today. Bring the intensity on the pitch."
        case .run: "Run day. Log it from Health — no sets to track here."
        case .sprint: "Sprint work today. Warm up properly before you go."
        case .conditioning: "Conditioning today. Push the engine, not the barbell."
        case .pool: "Pool day. Easy laps — active recovery, not a race."
        case .mobility: "Mobility today. Move well and recover — don't grind it."
        default: "Training today."
        }
    }

    /// The concrete cross-training session — headline + what to actually do —
    /// derived from the plan's type + duration. nil for gym/football (they have
    /// their own content). This is what makes a pool/run day a real prescription
    /// instead of just an icon and one line.
    private func cardioPrescription(for plan: WorkoutPlan) -> (headline: String, detail: String)? {
        let mins = plan.durationMinutes ?? 30
        switch plan.type {
        case .pool:
            if plan.notes?.localizedCaseInsensitiveContains("pre-match") == true {
                return (
                    "Pool flush · \(mins) min",
                    "Very easy continuous swim. Loosen the legs and keep breathing smooth — nothing hard the day before a match."
                )
            }
            return (
                "Continuous swim · \(mins) min",
                "Steady, relaxed pace the whole way — one continuous effort, no intervals. Active recovery: you should finish looser, not tired."
            )
        case .run:
            return (
                "Zone 2 easy run · \(mins) min",
                "Conversational pace — you should be able to talk in full sentences the whole way. Keep the heart rate easy; this builds the aerobic base without adding fatigue."
            )
        case .conditioning:
            return (
                "Conditioning · \(mins) min",
                "5 min easy warm-up, then 6 × (1 min hard / 90 sec easy), 5 min cool-down. Bike, row, or run the intervals — push the engine, not the barbell."
            )
        case .sprint:
            return (
                "Sprint work",
                "Warm up thoroughly first. 10–12 × 20–30 m at 90–95%, walk back for full recovery between reps. Stop if form breaks — quality over quantity."
            )
        case .mobility:
            return (
                "Mobility flow · \(mins) min",
                "Slow, controlled full-body flow — hips, shoulders, thoracic spine. This is recovery, not a session to grind."
            )
        default:
            return nil
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        TrainSkeleton()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Tide.s4) {
            TrainEmptyCard(systemImage: "figure.strengthtraining.traditional", title: "No workout planned")

            Button("Generate Today's Workout") {
                Task {
                    await viewModel.loadToday(modelContext: modelContext)
                }
            }
            .buttonStyle(.tidePrimary)
        }
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s10)
    }

    // MARK: - Helpers

    private var nextWorkoutType: String? {
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) else {
            return nil
        }
        // Look at tomorrow's plan in weekPlans (this week, Mon..Sun) if loaded.
        if let match = viewModel.weekPlans.first(where: { cal.isDate($0.date, inSameDayAs: tomorrow) }) {
            return match.type.displayName
        }
        // §6 Sunday gap — on a Sunday, tomorrow (Monday) falls in NEXT week,
        // which `weekPlans` never holds (it's this week only). Preview next
        // week's Monday so "up next" doesn't just go blank one day a week.
        let nextMonday = TrainingCalendar.mondayOfWeek(containing: tomorrow)
        return viewModel.previewWeekPlans(startingMonday: nextMonday, modelContext: modelContext)
            .first { cal.isDate($0.date, inSameDayAs: tomorrow) }?
            .type.displayName
    }

    /// Returns the most recent 3 ExerciseHistory entries for a given exercise (excluding today).
    private func lastThreePerformances(for exercise: Exercise) -> [ExerciseHistory] {
        let today = Calendar.current.startOfDay(for: Date())
        return (exercise.history ?? [])
            .filter { $0.date < today }
            .sorted { $0.date > $1.date }
            .prefix(3)
            .map(\.self)
    }

    /// Compact best-set summary for a session.
    private func bestSetSummary(history: ExerciseHistory) -> String {
        let unit = settings?.weightUnit ?? .kg
        if let r = history.bestSetReps, r > 0 {
            let bodyweight = history.exercise.map { StrengthStandards.isBodyweightLoaded($0.equipment) } ?? false
            return "\(WeightFormat.setLoad(kg: history.bestSetWeight, addedKg: history.bestSetAddedLoadKg, bodyweight: bodyweight, unit: unit)) × \(r)"
        }
        if let w = history.bestSetWeight, w > 0 {
            return WeightFormat.text(kg: w, unit: unit)
        }
        return "done"
    }

    /// Performance trend based on recent sessions.
    private struct PerformanceTrend {
        let symbol: String
        let color: Color
    }

    private func performanceTrend(sessions: [ExerciseHistory]) -> PerformanceTrend {
        guard sessions.count >= 2 else {
            return PerformanceTrend(symbol: "--", color: Tide.text3)
        }

        let latest = sessions[0]
        let previous = sessions[1]

        // Compare estimated 1RM first, fall back to best set weight
        let latestValue = latest.estimated1RM ?? latest.bestSetWeight ?? 0
        let previousValue = previous.estimated1RM ?? previous.bestSetWeight ?? 0

        if latestValue > previousValue {
            return PerformanceTrend(symbol: "\u{2191}", color: TideTrain.positive) // up arrow
        } else if latestValue < previousValue {
            return PerformanceTrend(symbol: "\u{2193}", color: Tide.danger) // down arrow
        } else {
            return PerformanceTrend(symbol: "\u{2192}", color: Tide.text3) // right arrow
        }
    }
}
