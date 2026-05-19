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
    private var showMobilityAlert = false
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
                    if viewModel.isLoading {
                        loadingState
                    } else if viewModel.isRestDay {
                        restDayContent
                    } else if let plan = viewModel.todayPlan {
                        workoutContent(plan: plan)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.bottom, 120) // space for floating button
            }
            .background(Color.tempoBgPrimary)

            // Floating Start Workout button
            if !viewModel.isRestDay, viewModel.todayPlan != nil, !viewModel.isLoading {
                startWorkoutButton
            }
        }
        .alert("Mobility Flows", isPresented: $showMobilityAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Mobility flows coming soon")
        }
        .task {
            await viewModel.loadToday(modelContext: modelContext)
        }
        .task {
            await refreshWorkoutSchedule()
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
            suggestedWindow = await services.calendar.suggestWorkoutWindow(for: Date())
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

                Text("Weights reduced 40% — same reps, lighter load.")
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
        }
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
            Button {
                showMobilityAlert = true
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
