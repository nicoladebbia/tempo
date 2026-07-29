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
    @Environment(\.modelContext)
    private var modelContext
    @Query
    private var allSettings: [UserSettings]
    @State
    private var showMobilityFlows = false
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
    /// §2.14 — add-exercise picker sheet.
    @State
    private var showAddExercise = false

    private let countdownTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

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

    private var settings: UserSettings? {
        allSettings.first
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: TempoSpacing.xl) {
                    // D4 §17 — month-boundary review card. Above the day branch
                    // on purpose: the month ends whether today is gym, field,
                    // or rest.
                    if let dueKey = viewModel.monthlyReviewDueKey {
                        monthlyReviewCard(dueKey)
                    }

                    // §18.4 — calendar-detected football, confirm-gated.
                    // Renders nothing when there's nothing to propose.
                    MatchProposalCard()

                    if viewModel.isLoading {
                        loadingState
                    } else if viewModel.isRestDay {
                        restDayContent
                    } else if let plan = viewModel.todayPlan {
                        if plan.type.isGymWorkout {
                            workoutContent(plan: plan)
                        } else {
                            // Non-gym training day (football, run, sprint,
                            // conditioning) — no exercises to log, so show a
                            // type-appropriate card instead of empty gym content.
                            nonGymContent(plan: plan)
                        }
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.bottom, 120) // space for floating button
            }
            .background(Color.tempoBgPrimary)
            // §2.16 — pull-to-refresh: full reload through the same coalesced
            // pipeline the .task uses (an in-flight load absorbs the pull).
            .refreshable {
                await viewModel.loadToday(modelContext: modelContext)
            }

            // Floating Start Workout button — ONLY on a loggable gym day.
            // Non-gym days (rest, mobility, football, run, sprint, conditioning)
            // have nothing to log, so no button is shown.
            if viewModel.canStartWorkout, !viewModel.isLoading {
                startWorkoutButton
            }
        }
        .sheet(isPresented: $showReorderSheet) {
            ExerciseReorderSheet(viewModel: viewModel)
        }
        .sheet(item: $swapTarget) { target in
            SwapExerciseSheet(viewModel: viewModel, target: target)
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
            // §21 — hand the watch today's real queue, and route wrist-logged
            // sets (including ones queued while the app was closed) onto the
            // plan. Registration replays any buffered actions immediately.
            services.watchConnectivity.setQuickActionHandler { [weak viewModel] action in
                guard action.action == .logSet, let viewModel else {
                    return
                }
                viewModel.applyWatchSetLog(
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
            // Any surface that mutates the workout re-syncs the wrist.
            viewModel.pushWorkoutToWatch()
        }
        .onReceive(countdownTick) { tick in
            now = tick
            // Saved event has started — drop the banner.
            if let ev = savedWorkoutEvent, ev.start <= tick {
                savedWorkoutEvent = nil
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
        VStack(spacing: TempoSpacing.lg) {
            // Workout type header
            workoutHeader(plan: plan)

            // Deload week banner
            if viewModel.isDeloadWeek {
                deloadBanner
            }

            // §16 — venue propose-confirm (renders only with a learned pattern
            // for today's weekday; collapses once answered or dismissed).
            VenueProposalCard()

            // D2 — the daily readiness prescription (supersedes the legacy
            // pendingAdjustment card). Modality + intensity + why + blocks/cues.
            // Reads WHY/intensity from DailySession, sets from the linked plan.
            if let session = viewModel.dailySession {
                dailySessionCard(session)
            }

            #if DEBUG
            // Force a fresh coach run in-place (no .task / relaunch dependency —
            // the flag + direct call run in one stack). Verifies the daily loop.
            Button("⟳ Run coach now (force, DEBUG)") {
                UserDefaults.standard.set(true, forKey: "tempo.debug.forceDailyRerun")
                Task { await viewModel.runDailyReadinessSession(modelContext: modelContext) }
            }
            .font(.tempoCaption1)
            .foregroundStyle(Color.tempoSignal)
            #endif

            // Saved-event countdown takes precedence over the suggestion;
            // both are non-blocking (Phase 4 + follow-up).
            if let saved = savedWorkoutEvent {
                workoutCountdownBanner(saved)
            } else if let window = suggestedWindow {
                workoutWindowBanner(window)
            }

            // Recovery badge bar
            // Per MODULE_TRAINING.md Section 2.5
            recoveryBadge(plan: plan)

            // Workout meta bar
            // Per MODULE_TRAINING.md Section 2.6
            workoutMeta(plan: plan)

            // §14 #3 — one-tap session RPE, only after completion.
            sessionRPESection(plan: plan)

            // Exercise list
            // Per MODULE_TRAINING.md Section 2.7
            exerciseList(plan: plan)
        }
    }

    // MARK: - Workout Header

    private func workoutHeader(plan: WorkoutPlan) -> some View {
        VStack(spacing: TempoSpacing.xs) {
            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            Text(plan.type.displayName.uppercased() + " DAY")
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .padding(.top, TempoSpacing.md)
    }

    // MARK: - Deload Banner

    private var deloadBanner: some View {
        HStack(spacing: TempoSpacing.sm) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.tempoRecoveryYellow)

            VStack(alignment: .leading, spacing: 2) {
                Text("DELOAD WEEK")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoRecoveryYellow)

                Text(viewModel.deloadStyle.blurb)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoRecoveryYellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
                .stroke(Color.tempoRecoveryYellow.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Live Recovery Adjustment Card (Phase 2 Fix 2.4)

    


    // MARK: - Daily Session Card (D2 — the readiness prescription)

    @ViewBuilder
    private func dailySessionCard(_ session: DailySession) -> some View {
        if session.userOverrode {
            // §8 connect — he declined the brain's move. One honest line; the
            // plan row (restored) is the day again.
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(Color.tempoWarning)
                Text("Coach called \(session.modality.uppercased()). You kept \(viewModel.todayPlan?.type.displayName.uppercased() ?? "THE PLAN"). Your call.")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
                Spacer()
            }
            .padding(TempoSpacing.cardPadding)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        } else {
            dailySessionCardBody(session)
        }
    }

    private func dailySessionCardBody(_ session: DailySession) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack {
                Text(session.modality.uppercased())
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Text(session.intensity.rawValue.uppercased())
                    .font(.tempoCaption2)
                    .foregroundStyle(intensityColor(session.intensity))
                    .padding(.horizontal, TempoSpacing.sm)
                    .padding(.vertical, 4)
                    .background(intensityColor(session.intensity).opacity(0.15))
                    .clipShape(Capsule())
            }

            // Floor provenance — honest about how this was produced.
            if session.wasDowngraded || session.source != .brain {
                Text(sessionProvenance(session))
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            // Short why → tap for full.
            Text(session.shortWhy)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)

            if let full = session.fullWhy, !full.isEmpty {
                if showFullWhy {
                    Text(full)
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
                Button(showFullWhy ? "Less" : "Why?") {
                    withAnimation { showFullWhy.toggle() }
                }
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoSignal)
            }

            // Blocks (non-gym detail + cues; gym sets render in the exercise
            // list). §21 composite days render grouped by part with a start-time
            // header, and the gym part gets a pointer line so its slot is visible.
            let parts = session.blocks.parts
            ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                if parts.count >= 2 {
                    Text(partHeader(part.scheduledMin))
                        .font(.tempoCaption1)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .padding(.top, TempoSpacing.xs)
                }
                ForEach(Array(part.blocks.enumerated()), id: \.offset) { _, block in
                    if block.kind != .gym {
                        blockRow(block)
                    } else if parts.count >= 2 {
                        Text("Gym \(block.split.map { "(\($0))" } ?? "") — exercises below")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
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
               let second = plan.secondarySessionType {
                Divider().overlay(Color.tempoTextTertiary.opacity(0.3))
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: plan.secondaryCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(plan.secondaryCompleted ? Color.tempoSignal : Color.tempoTextTertiary)
                    Text("\(second.displayName) — second session")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .strikethrough(plan.secondaryCompleted, color: Color.tempoTextTertiary)
                    Spacer()
                    Button(plan.secondaryCompleted ? "Undo" : "Mark done") {
                        HapticManager.selection()
                        viewModel.toggleSecondarySessionComplete(modelContext: modelContext)
                    }
                    .font(.tempoCaption1)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.tempoSignal)
                }
            }

            // §8 connect — the brain moved the day off the planned modality.
            // Say so, and hand him the override. Brain-chosen moves only: a
            // SEVERE floor skip never stashes plannedTypeRaw, so this row
            // can't appear on a locked recovery day.
            if let plan = viewModel.todayPlan,
               plan.status == .planned,
               let plannedRaw = plan.plannedTypeRaw,
               let plannedType = WorkoutType(rawValue: plannedRaw) {
                Divider().overlay(Color.tempoTextTertiary.opacity(0.3))
                HStack {
                    Text("Plan said \(plannedType.displayName.uppercased()).")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                    Spacer()
                    Button("Keep \(plannedType.displayName)") {
                        HapticManager.selection()
                        viewModel.keepPlannedWorkout(modelContext: modelContext)
                    }
                    .font(.tempoCaption1)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.tempoSignal)
                }
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
    }

    /// §21 — part header for a composite day ("AT 16:00" / "ANYTIME" for the
    /// untimed anchor).
    private func partHeader(_ scheduledMin: Int?) -> String {
        scheduledMin.map { "AT \(VenuePatternMath.clockLabel($0))" } ?? "ANYTIME"
    }

    @ViewBuilder
    private func blockRow(_ block: SessionBlockDTO) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(block.label)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
            if let cue = block.cue, !cue.isEmpty {
                Text(cue)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func intensityColor(_ intensity: SessionIntensity) -> Color {
        switch intensity {
        case .recovery, .easy: return Color.tempoRecoveryGreen
        case .moderate: return Color.tempoRecoveryYellow
        case .hard, .max: return Color.tempoRecoveryRed
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
        HStack(spacing: TempoSpacing.sm) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.tempoSignal)

            VStack(alignment: .leading, spacing: 2) {
                Text("BEST WINDOW TODAY")
                    .font(.tempoCaption2)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)

                Text("\(timeString(window.start)) – \(timeString(window.end))")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
            }

            Spacer()

            Button {
                showAddToCalendar = true
                HapticManager.selection()
            } label: {
                Text("Add to Calendar")
                    .font(.tempoCaption1)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextInverse)
                    .padding(.horizontal, TempoSpacing.sm)
                    .padding(.vertical, TempoSpacing.xs)
                    .background(Color.tempoSignal)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoSignal.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
                .stroke(Color.tempoSignal.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Workout Countdown Banner

    // Shown once an event is saved to the calendar: live "Gym in Xh Ym"
    // counting down to the saved start, refreshed each minute by
    // `countdownTick`. Clears itself when the start passes.

    private func workoutCountdownBanner(_ event: DateInterval) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            Image(systemName: "figure.run")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.tempoSignal)

            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT WORKOUT")
                    .font(.tempoCaption2)
                    .tracking(TempoTracking.drillLabel)
                    .foregroundStyle(Color.tempoTextSecondary)

                Text("Gym in \(countdownString(to: event.start)) — \(timeString(event.start))")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
            }

            Spacer()
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoSignal.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
                .stroke(Color.tempoSignal.opacity(0.3), lineWidth: 1)
        )
    }

    /// "3h 32m" / "47m" / "soon" — derived from `now` so it re-renders on
    /// each `countdownTick`.
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

    // MARK: - Recovery Badge

    // Per MODULE_TRAINING.md Section 2.5

    private func recoveryBadge(plan: WorkoutPlan) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            Circle()
                .fill(recoveryDotColor(plan: plan))
                .frame(width: 10, height: 10)

            Text(recoveryText(plan: plan))
                .font(.tempoBody)
                .fontWeight(.medium)
                .foregroundStyle(Color.tempoTextPrimary)

            Text("·")
                .foregroundStyle(Color.tempoTextTertiary)

            Text(adjustmentLabel(plan: plan))
                .font(.tempoBody)
                .foregroundStyle(recoveryDotColor(plan: plan))

            Spacer()
        }
        .padding(.horizontal, TempoSpacing.md)
        .padding(.vertical, TempoSpacing.sm)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // MARK: - Workout Meta

    // Per MODULE_TRAINING.md Section 2.6

    private func workoutMeta(plan: WorkoutPlan) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.xxs) {
                Image(systemName: "timer")
                    .font(.tempoCaption1)
                Text("~\(plan.durationMinutes ?? estimatedDuration(plan: plan)) min")
                    .font(.tempoCaption1)
            }
            .foregroundStyle(Color.tempoTextSecondary)

            Text("·")
                .foregroundStyle(Color.tempoTextTertiary)

            Text("\(plan.orderedExercises.count) exercises")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)

            Text("·")
                .foregroundStyle(Color.tempoTextTertiary)

            Text("\(plan.totalSets) sets")
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)

            Spacer()

            // §2.15 — reorder entry point. Planned days only: mid-session
            // reordering would fight currentExerciseIndex, and a completed
            // day's order is history.
            if plan.status == .planned, plan.orderedExercises.count > 1 {
                Button {
                    showReorderSheet = true
                    HapticManager.selection()
                } label: {
                    HStack(spacing: TempoSpacing.xxs) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Reorder")
                            .font(.tempoCaption1)
                    }
                    .foregroundStyle(Color.tempoAmber)
                }
            }
        }
    }

    // MARK: - Monthly Review Card (D4 §17 — the month-boundary ritual)

    private func monthlyReviewCard(_ monthKey: String) -> some View {
        Button {
            activeReviewKey = monthKey
            showMonthlyReview = true
        } label: {
            HStack(spacing: TempoSpacing.md) {
                Image(systemName: "checklist.checked")
                    .font(.tempoTitle3)
                    .foregroundStyle(Color.tempoSignal)
                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    Text("MONTH'S OVER. DEBRIEF.")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text("5 questions, then your report. 2 minutes.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .padding(TempoSpacing.lg)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
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
            if let logged = plan.sessionRPE {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.tempoSignal)
                    Text("Session RPE logged: \(logged)/10")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                    Spacer()
                }
                .padding(TempoSpacing.lg)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    Text("HOW HARD WAS THAT?")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                    Text("Whole session. 1 = nothing, 10 = max effort.")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                    sessionRPERow(1 ... 5)
                    sessionRPERow(6 ... 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(TempoSpacing.lg)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
            }
        }
    }

    private func sessionRPERow(_ range: ClosedRange<Int>) -> some View {
        HStack(spacing: TempoSpacing.sm) {
            ForEach(range, id: \.self) { value in
                Button {
                    HapticManager.selection()
                    viewModel.recordSessionRPE(value, modelContext: modelContext)
                } label: {
                    Text("\(value)")
                        .font(.tempoTitle3)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.tempoBgPrimary)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                }
            }
        }
    }

    // MARK: - Exercise List

    // Per MODULE_TRAINING.md Section 2.7

    private func exerciseList(plan: WorkoutPlan) -> some View {
        let exercises = plan.orderedExercises
        let groups = groupedBySupersets(exercises)

        return VStack(spacing: TempoSpacing.sm) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                if group.count > 1 {
                    // Superset group: shared card with connecting indicator
                    supersetCard(exercises: group, startIndex: exercises.firstIndex(where: { $0.id == group[0].id }) ?? 0)
                } else if let single = group.first {
                    let idx = (exercises.firstIndex(where: { $0.id == single.id }) ?? 0)
                    exerciseCard(index: idx + 1, plannedExercise: single)
                }
            }

            // §2.14 — dashed add-exercise entry point (wireframe Screen 11).
            if plan.status == .planned || plan.status == .inProgress {
                addExerciseButton
            }
        }
    }

    private var addExerciseButton: some View {
        Button {
            showAddExercise = true
        } label: {
            HStack(spacing: TempoSpacing.xs) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                Text("Add Exercise")
                    .font(.tempoSubheadline)
            }
            .foregroundStyle(Color.tempoTextSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .overlay(
                RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous)
                    .stroke(
                        Color.tempoTextTertiary.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                    )
            )
        }
        .buttonStyle(.plain)
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

    private func supersetCard(exercises: [PlannedExercise], startIndex: Int) -> some View {
        VStack(spacing: 0) {
            // Superset header badge
            HStack(spacing: TempoSpacing.xxs) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .semibold))
                Text("SUPERSET")
                    .font(.tempoCaption2)
                    .fontWeight(.bold)
            }
            .foregroundStyle(Color.tempoSignal)
            .padding(.horizontal, TempoSpacing.sm)
            .padding(.vertical, 4)

            // Exercise cards with connecting line
            ForEach(Array(exercises.enumerated()), id: \.element.id) { idx, plannedEx in
                HStack(spacing: TempoSpacing.sm) {
                    // Vertical connecting line
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(idx == 0 ? Color.clear : Color.tempoSignal.opacity(0.4))
                            .frame(width: 2)

                        Circle()
                            .fill(Color.tempoSignal)
                            .frame(width: 8, height: 8)

                        Rectangle()
                            .fill(idx == exercises.count - 1 ? Color.clear : Color.tempoSignal.opacity(0.4))
                            .frame(width: 2)
                    }
                    .frame(width: 8)

                    // Exercise card content
                    exerciseCard(index: startIndex + idx + 1, plannedExercise: plannedEx)
                }
            }
        }
        .padding(TempoSpacing.xs)
        .background(Color.tempoSurfaceCard.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .stroke(Color.tempoSignal.opacity(0.2), lineWidth: 1)
        )
    }

    private func exerciseCard(index: Int, plannedExercise: PlannedExercise) -> some View {
        Group {
            if let exercise = plannedExercise.exercise {
                NavigationLink(destination: ExerciseDetailView(exercise: exercise)) {
                    exerciseCardContent(index: index, plannedExercise: plannedExercise)
                }
                .buttonStyle(.plain)
            } else {
                exerciseCardContent(index: index, plannedExercise: plannedExercise)
            }
        }
        // §2.13 — long-press swap (TESTING_STRATEGY UT-005 / M-T-008).
        .contextMenu {
            if canSwap(plannedExercise) {
                Button {
                    swapTarget = plannedExercise
                } label: {
                    Label("Swap Exercise", systemImage: "arrow.triangle.2.circlepath")
                }
            }
        }
    }

    private func exerciseCardContent(index: Int, plannedExercise: PlannedExercise) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            // Row 1: Number + Name + Muscle group + chevron
            HStack {
                Text("\(index)")
                    .font(.tempoCaption1)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .frame(width: 20, alignment: .leading)

                Text(plannedExercise.exercise?.name.uppercased() ?? "EXERCISE")
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(1)

                Spacer()

                // §11.12 — intensity zone (HEAVY/BUILD/PUMP), recovered from
                // the rep target; only e1RM-anchored prescriptions carry RIR,
                // so gate on that to avoid mislabeling legacy 8/12 fallbacks.
                if let firstWorking = plannedExercise.orderedSets.first(where: { !$0.isWarmup }),
                   firstWorking.targetRIR != nil {
                    let zone = PrescriptionMath.zoneLabel(forReps: firstWorking.targetReps)
                    Text(zone)
                        .font(.tempoCaption2)
                        .fontWeight(.bold)
                        .foregroundStyle(zone == "HEAVY" ? Color.tempoSignal : Color.tempoAmber)
                        .padding(.horizontal, TempoSpacing.xs)
                        .padding(.vertical, 2)
                        .background((zone == "HEAVY" ? Color.tempoSignal : Color.tempoAmber).opacity(0.12))
                        .clipShape(Capsule())
                }

                if let muscleGroup = plannedExercise.exercise?.muscleGroup {
                    Text(muscleGroup.displayName.uppercased())
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .padding(.horizontal, TempoSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.tempoBgSecondary)
                        .clipShape(Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            // Row 2: Sets x Reps @ Weight
            if let sets = plannedExercise.sets, let firstSet = sets.first {
                HStack(spacing: TempoSpacing.xxs) {
                    Text(prescriptionText(sets: sets, firstSet: firstSet))
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)

                    // Progressive overload indicator
                    if let notes = plannedExercise.workoutPlan?.notes,
                       notes.contains("Increased")
                    {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.tempoSignal)
                    }
                }
            }

            // Row 3: Last 3 sessions' performance with trend indicator
            if let exercise = plannedExercise.exercise {
                let recentSessions = lastThreePerformances(for: exercise)
                if !recentSessions.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: TempoSpacing.xxs) {
                            Text("Recent:")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)

                            // Trend indicator
                            let trend = performanceTrend(sessions: recentSessions)
                            Text(trend.symbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(trend.color)
                        }

                        // Last 3 best sets
                        HStack(spacing: TempoSpacing.sm) {
                            ForEach(Array(recentSessions.enumerated()), id: \.offset) { idx, session in
                                Text(bestSetSummary(history: session))
                                    .font(.system(size: 10))
                                    .foregroundStyle(idx == 0 ? Color.tempoTextSecondary : Color.tempoTextTertiary)
                            }
                        }
                    }
                }
            }

            // Row 4: Equipment hint
            if let equipment = plannedExercise.exercise?.equipment {
                Text(equipmentHint(equipment))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    private func equipmentHint(_ equipment: Equipment) -> String {
        switch equipment {
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .cable: "Cable Machine"
        case .machine: "Machine"
        case .bodyweight: "Bodyweight"
        case .kettlebell: "Kettlebell"
        default: equipment.rawValue.capitalized
        }
    }

    /// SF Symbol for equipment type — used in place of emoji.
    private func equipmentIcon(_ equipment: Equipment) -> String {
        switch equipment {
        case .barbell: "figure.strengthtraining.traditional"
        case .dumbbell: "dumbbell.fill"
        case .cable: "cable.connector"
        case .machine: "gearshape.fill"
        case .bodyweight: "figure.flexibility"
        case .kettlebell: "figure.strengthtraining.functional"
        default: "figure.mixed.cardio"
        }
    }

    // MARK: - Start Workout Button

    // Per MODULE_TRAINING.md Section 2.9

    private var startWorkoutButton: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .frame(height: 20)
                .blur(radius: 10)

            Button {
                HapticManager.impact(.heavy)
                viewModel.startWorkout()
                showActiveWorkout = true
            } label: {
                HStack(spacing: TempoSpacing.sm) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15))
                    Text("START WORKOUT")
                        .font(.tempoHeadline)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.tempoSignal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.md)
        }
        .background(Color.tempoBgPrimary.opacity(0.95))
    }

    // MARK: - Rest Day Content

    // Per MODULE_TRAINING.md Section 2.10

    private var restDayContent: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer().frame(height: TempoSpacing.xxxl)

            TimelineView(.everyMinute) { context in
                Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }

            Text("REST DAY")
                .font(.tempoTitle1)
                .foregroundStyle(Color.tempoTextPrimary)

            // §8 connect — a brain-reshaped rest day (planned pool → rest)
            // renders THIS content, so the prescription's why + the "keep
            // planned workout" override must live here too, not just on
            // gym/non-gym days.
            if let session = viewModel.dailySession {
                dailySessionCard(session)
            }

            Image(systemName: "figure.yoga")
                .font(.system(size: 60))
                .foregroundStyle(Color.tempoTextTertiary)

            VStack(spacing: TempoSpacing.sm) {
                Text("Your body builds muscle while you rest.")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .multilineTextAlignment(.center)

                if let nextType = nextWorkoutType {
                    VStack(spacing: TempoSpacing.xxs) {
                        Text("Next workout: Tomorrow")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                        Text(nextType.uppercased())
                            .font(.tempoHeadline)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                }
            }

            // Mobility flow button
            mobilityFlowButton
        }
    }

    private var mobilityFlowButton: some View {
        Button {
            showMobilityFlows = true
        } label: {
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: "figure.flexibility")
                Text("Start a Mobility Flow")
            }
            .font(.tempoHeadline)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.tempoSurfaceCard)
            .foregroundStyle(Color.tempoTextPrimary)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        }
    }

    // MARK: - Non-Gym Training Day Content

    // Shown for training days that aren't loggable gym sessions — football,
    // run, sprint, conditioning. These have no exercises/sets to log, so there
    // is no "Start Workout" button; this card just tells the user what today is.
    private func nonGymContent(plan: WorkoutPlan) -> some View {
        // §11.7 — compact: the old xxl spacing + top spacer + 60pt icon pushed
        // half the content below the fold; one screen, no dead air.
        VStack(spacing: TempoSpacing.md) {
            // Day header as one compact row: icon + type + date.
            HStack(spacing: TempoSpacing.sm) {
                Image(systemName: nonGymIcon(for: plan.type))
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.tempoTextSecondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(plan.type.displayName.uppercased())
                        .font(.tempoTitle2)
                        .foregroundStyle(Color.tempoTextPrimary)
                    TimelineView(.everyMinute) { context in
                        Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                Spacer()
                if let nextType = nextWorkoutType {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("TOMORROW")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                        Text(nextType.uppercased())
                            .font(.tempoCaption1)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.tempoTextPrimary)
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.lg)
            .padding(.top, TempoSpacing.sm)

            Text(nonGymMessage(for: plan.type))
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.lg)

            // §16 — venue propose-confirm, same placement as the gym path.
            VenueProposalCard()

            // D2 — the readiness prescription IS the content on a non-gym day
            // (modality/intensity/why + blocks with cues; there's no exercise list).
            if let session = viewModel.dailySession {
                dailySessionCard(session)
            }

            // §10 — a mobility DAY gets the guided flows as its session (the
            // flow's completion marks the day done through the non-gym path).
            if plan.type == .mobility, plan.status != .completed {
                mobilityFlowButton
                    .padding(.horizontal, TempoSpacing.lg)
            }

            // §13 — running days link to the run history (HealthKit-mirrored
            // distance/pace/splits).
            if plan.type == .run || plan.type == .sprint || plan.type == .conditioning {
                NavigationLink(destination: RunHistoryView()) {
                    HStack(spacing: TempoSpacing.sm) {
                        Image(systemName: "figure.run")
                        Text("Your Runs")
                    }
                    .font(.tempoHeadline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.tempoSurfaceCard)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
                }
                .padding(.horizontal, TempoSpacing.lg)
            }

            // The actual cross-training prescription (what to DO), so a cardio
            // day isn't just an icon + one line. Reads type + duration off the
            // plan. FALLBACK ONLY: when the daily brain already produced a
            // DailySession card above, defer to it — don't show two prescriptions.
            if viewModel.dailySession == nil, let rx = cardioPrescription(for: plan) {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    Text(rx.headline)
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(rx.detail)
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(TempoSpacing.lg)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
                .padding(.horizontal, TempoSpacing.lg)
            }

            // Whoop activity confirm / saved summary.
            nonGymActivitySection(plan: plan)

            // §14 #3 — one-tap session RPE, only after completion.
            sessionRPESection(plan: plan)
        }
        .task(id: plan.id) {
            await viewModel.loadNonGymActivity(modelContext: modelContext)
        }
    }

    // The strain/HR confirm-and-save block beneath the non-gym card.
    @ViewBuilder
    private func nonGymActivitySection(plan: WorkoutPlan) -> some View {
        switch viewModel.nonGymActivityState {
        case .loading:
            ProgressView()
                .padding(.top, TempoSpacing.md)

        case let .foundTagged(summary):
            VStack(spacing: TempoSpacing.md) {
                activityStatsRow(summary)
                confirmButton(
                    title: "CONFIRM — THAT WAS \(plan.type.displayName.uppercased())",
                    summary: summary
                )
            }

        case let .foundUntagged(summary):
            VStack(spacing: TempoSpacing.md) {
                Text("Found an activity today — was this \(plan.type.displayName.lowercased())?")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
                    .multilineTextAlignment(.center)
                activityStatsRow(summary)
                confirmButton(title: "YES, LOG IT", summary: summary)
                Button {
                    HapticManager.impact(.light)
                    viewModel.dismissNonGymActivity()
                } label: {
                    Text("No — that wasn't \(plan.type.displayName.lowercased())")
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }

        case .none, .dismissed:
            confirmButton(
                title: "LOG THAT I PLAYED",
                summary: nil
            )

        case let .saved(summary):
            VStack(spacing: TempoSpacing.sm) {
                HStack(spacing: TempoSpacing.xs) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.tempoRecoveryGreen)
                    Text("Logged")
                        .font(.tempoHeadline)
                        .foregroundStyle(Color.tempoTextPrimary)
                }
                if let summary {
                    activityStatsRow(summary)
                }
            }
            .padding(.top, TempoSpacing.md)
        }
    }

    private func activityStatsRow(_ s: TrainingViewModel.WhoopActivitySummary) -> some View {
        VStack(spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.lg) {
                activityStat(value: String(format: "%.1f", s.strain), label: "Strain")
                activityStat(value: "\(Int(s.durationMinutes))m", label: "Duration")
                activityStat(value: "\(Int(s.averageHeartRate))", label: "Avg HR")
                activityStat(value: "\(Int(s.caloriesBurned))", label: "Cal")
            }
            sweatHydrationNote(s)
        }
        .padding(.vertical, TempoSpacing.md)
        .frame(maxWidth: .infinity)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    // Estimated sweat loss + hydration guidance from the same HydrationMath
    // the daily target uses. Shown as a range (rough estimate), with an
    // electrolyte nudge for larger losses.
    @ViewBuilder
    private func sweatHydrationNote(_ s: TrainingViewModel.WhoopActivitySummary) -> some View {
        if let range = HydrationMath.sweatLossLitres(
            caloriesBurned: s.caloriesBurned,
            durationMinutes: s.durationMinutes
        ) {
            let needsElectrolytes = HydrationMath.needsElectrolytes(range.lowerBound)
            VStack(spacing: 2) {
                HStack(spacing: TempoSpacing.xs) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.tempoElectric)
                    Text(String(format: "~%.1f–%.1f L lost — drink to replace", range.lowerBound, range.upperBound))
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                if needsElectrolytes {
                    Text("Add electrolytes, not just water.")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .padding(.top, TempoSpacing.xxs)
        }
    }

    private func activityStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
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
                .font(.tempoHeadline)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.tempoSignal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
        }
        .padding(.top, TempoSpacing.sm)
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
                return ("Pool flush · \(mins) min",
                        "Very easy continuous swim. Loosen the legs and keep breathing smooth — nothing hard the day before a match.")
            }
            return ("Continuous swim · \(mins) min",
                    "Steady, relaxed pace the whole way — one continuous effort, no intervals. Active recovery: you should finish looser, not tired.")
        case .run:
            return ("Zone 2 easy run · \(mins) min",
                    "Conversational pace — you should be able to talk in full sentences the whole way. Keep the heart rate easy; this builds the aerobic base without adding fatigue.")
        case .conditioning:
            return ("Conditioning · \(mins) min",
                    "5 min easy warm-up, then 6 × (1 min hard / 90 sec easy), 5 min cool-down. Bike, row, or run the intervals — push the engine, not the barbell.")
        case .sprint:
            return ("Sprint work",
                    "Warm up thoroughly first. 10–12 × 20–30 m at 90–95%, walk back for full recovery between reps. Stop if form breaks — quality over quantity.")
        case .mobility:
            return ("Mobility flow · \(mins) min",
                    "Slow, controlled full-body flow — hips, shoulders, thoracic spine. This is recovery, not a session to grind.")
        default:
            return nil
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: TempoSpacing.lg) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Generating your workout...")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 100)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TempoSpacing.lg) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 48))
                .foregroundStyle(Color.tempoTextTertiary)

            Text("No workout planned")
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextSecondary)

            Button("Generate Today's Workout") {
                Task {
                    await viewModel.loadToday(modelContext: modelContext)
                }
            }
            .buttonStyle(.tempoPrimary)
        }
        .padding(.top, 100)
    }

    // MARK: - Helpers

    private func recoveryDotColor(plan: WorkoutPlan) -> Color {
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 {
            return Color.tempoRecoveryGreen
        }
        if adj >= 0.6 {
            return Color.tempoRecoveryYellow
        }
        return Color.tempoRecoveryRed
    }

    private func recoveryText(plan: WorkoutPlan) -> String {
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 {
            return "Green Recovery"
        }
        if adj >= 0.6 {
            return "Yellow Recovery"
        }
        return "Red Recovery"
    }

    private func adjustmentLabel(plan: WorkoutPlan) -> String {
        let adj = plan.recoveryAdjustment
        if adj >= 1.0 {
            return "Full Volume"
        }
        if adj >= 0.8 {
            return "-20% Volume"
        }
        if adj >= 0.75 {
            return "-20% Volume, Lighter Load"
        }
        return "Swapped to Mobility"
    }

    private func estimatedDuration(plan: WorkoutPlan) -> Int {
        let exercises = plan.orderedExercises
        guard !exercises.isEmpty else {
            return 20
        }

        var totalMinutes = 5.0 // Warmup period
        let exerciseCount = exercises.count

        for (index, plannedEx) in exercises.enumerated() {
            let sets = plannedEx.orderedSets
            let isCompound = plannedEx.exercise?.isCompound ?? false

            for set in sets {
                if set.isWarmup {
                    totalMinutes += 1.0 // Warmup sets: 1 min each
                } else if isCompound {
                    totalMinutes += 2.5 // Working compound sets: 2.5 min (set + rest)
                } else {
                    totalMinutes += 1.5 // Working isolation sets: 1.5 min (set + rest)
                }
            }

            // Between-exercise transition (not after the last exercise)
            if index < exerciseCount - 1 {
                totalMinutes += 1.0
            }
        }

        totalMinutes += 3.0 // Cooldown

        return max(20, Int(totalMinutes.rounded()))
    }

    private func prescriptionText(sets: [PlannedSet], firstSet: PlannedSet) -> String {
        let workingSets = sets.filter { !$0.isWarmup }
        let warmupSets = sets.filter(\.isWarmup)
        let setCount = workingSets.count
        let reps = (workingSets.first ?? firstSet).targetReps
        let unit = settings?.weightUnit ?? .kg

        var text: String
        if let weight = (workingSets.first ?? firstSet).targetWeight, weight > 0 {
            let displayWeight = WeightUnit.kg.convert(weight, to: unit)
            text = "\(setCount) x \(reps) @ \(Int(displayWeight))\(unit.abbreviation)"
        } else {
            text = "\(setCount) x \(reps) (BW)"
        }

        // §11.12 — effort target rides the prescription line when the
        // e1RM-anchored path set one.
        if let rir = (workingSets.first ?? firstSet).targetRIR {
            text += " · RIR \(rir)"
        }

        if !warmupSets.isEmpty {
            text += " + \(warmupSets.count) warmup"
        }

        return text
    }

    private var nextWorkoutType: String? {
        // Look at tomorrow's plan in weekPlans if loaded
        viewModel.weekPlans
            .first { Calendar.current.isDateInTomorrow($0.date) }
            .map(\.type.displayName)
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
        if let w = history.bestSetWeight, w > 0 {
            let converted = WeightUnit.kg.convert(w, to: unit)
            if let r = history.bestSetReps {
                return "\(Int(converted))\(unit.abbreviation)x\(r)"
            }
            return "\(Int(converted))\(unit.abbreviation)"
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
            return PerformanceTrend(symbol: "--", color: Color.tempoTextTertiary)
        }

        let latest = sessions[0]
        let previous = sessions[1]

        // Compare estimated 1RM first, fall back to best set weight
        let latestValue = latest.estimated1RM ?? latest.bestSetWeight ?? 0
        let previousValue = previous.estimated1RM ?? previous.bestSetWeight ?? 0

        if latestValue > previousValue {
            return PerformanceTrend(symbol: "\u{2191}", color: Color.tempoRecoveryGreen) // up arrow
        } else if latestValue < previousValue {
            return PerformanceTrend(symbol: "\u{2193}", color: Color.tempoRecoveryRed) // down arrow
        } else {
            return PerformanceTrend(symbol: "\u{2192}", color: Color.tempoTextTertiary) // right arrow
        }
    }
}

// MARK: - ExerciseReorderSheet (§2.15)

/// Drag-to-reorder for today's planned exercises. A dedicated List because
/// `.onMove` is List-only — the styled card stack in TodayWorkoutView can't
/// host it. Order writes through `moveExercises` (which renumbers
/// `PlannedExercise.order`) and persists immediately; moving one member of a
/// superset out of adjacency deliberately splits that superset (grouping is
/// consecutive-run based).
private struct ExerciseReorderSheet: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.todayPlan?.orderedExercises ?? [], id: \.id) { ex in
                    HStack(spacing: TempoSpacing.sm) {
                        Text(ex.exercise?.name ?? "Exercise")
                            .font(.tempoBody)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Spacer()
                        if ex.supersetGroup != nil {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.tempoSignal)
                        }
                    }
                    .listRowBackground(Color.tempoSurfaceCard)
                }
                .onMove { source, destination in
                    viewModel.moveExercises(from: source, to: destination)
                    try? modelContext.save()
                    HapticManager.selection()
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - SwapExerciseSheet (§2.13)

/// Alternatives for one planned slot — same muscle group, closest movement
/// pattern first. Selecting one swaps the movement in place (order and
/// superset pairing kept, prescription rebuilt for the new lift).
private struct SwapExerciseSheet: View {
    @Bindable
    var viewModel: TrainingViewModel
    let target: PlannedExercise
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let alternatives = viewModel.swapAlternatives(for: target, modelContext: modelContext)
                if alternatives.isEmpty {
                    Text("No alternatives for this muscle group.")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .listRowBackground(Color.tempoSurfaceCard)
                } else {
                    ForEach(alternatives, id: \.id) { exercise in
                        Button {
                            viewModel.swapExercise(target, with: exercise, modelContext: modelContext)
                            dismiss()
                        } label: {
                            ExercisePickRow(exercise: exercise)
                        }
                        .listRowBackground(Color.tempoSurfaceCard)
                    }
                    // §2.13b — swaps teach the planner.
                    Text("Tempo remembers your pick — future days prescribe it instead. Swap back anytime to undo.")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
            .navigationTitle("Swap \(target.exercise?.name ?? "Exercise")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - AddExerciseSheet (§2.14)

/// Full-library picker for appending an exercise to today's plan. Searchable,
/// sectioned by muscle group; movements already in the plan are excluded.
private struct AddExerciseSheet: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Query(sort: \Exercise.name)
    private var allExercises: [Exercise]
    @State
    private var searchText = ""

    private var candidates: [Exercise] {
        let inPlan = Set(
            (viewModel.todayPlan?.orderedExercises ?? []).compactMap { $0.exercise?.id }
        )
        return allExercises.filter { exercise in
            guard !inPlan.contains(exercise.id) else {
                return false
            }
            guard !searchText.isEmpty else {
                return true
            }
            return exercise.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Muscle-group sections, ordered by group display name.
    private var sections: [(group: MuscleGroup, exercises: [Exercise])] {
        Dictionary(grouping: candidates, by: \.muscleGroup)
            .map { (group: $0.key, exercises: $0.value) }
            .sorted { $0.group.displayName < $1.group.displayName }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.group) { section in
                    Section(section.group.displayName.uppercased()) {
                        ForEach(section.exercises, id: \.id) { exercise in
                            Button {
                                viewModel.addExercise(exercise, modelContext: modelContext)
                                dismiss()
                            } label: {
                                ExercisePickRow(exercise: exercise)
                            }
                            .listRowBackground(Color.tempoSurfaceCard)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.tempoBgPrimary)
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Shared row for the swap/add pickers: name + equipment, compound badge.
private struct ExercisePickRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: TempoSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text(exercise.equipment.rawValue.capitalized)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            Spacer()
            if exercise.isCompound {
                Text("COMPOUND")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .padding(.horizontal, TempoSpacing.xs)
                    .padding(.vertical, 2)
                    .background(Color.tempoBgSecondary)
                    .clipShape(Capsule())
            }
        }
    }
}
