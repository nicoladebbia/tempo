//
// WorkoutHistoryView.swift
// Tempo
//
// Created by Tempo on 08/05/2026.
//
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Workout History View

// Shows completed workouts sorted by date descending.
// Tapping a card expands to show per-exercise detail (sets/reps/weight).

struct WorkoutHistoryView: View {
    @Query(
        filter: #Predicate<WorkoutPlan> { $0.statusRaw == "completed" },
        sort: \WorkoutPlan.date,
        order: .reverse
    )
    private var completedWorkouts: [WorkoutPlan]

    @Query
    private var userSettings: [UserSettings]

    /// All captured set feedback. Bounded (one row per logged set); built
    /// into a `[setID: SetFeedback]` lookup so expanded rows can show
    /// RPE/breath/form. Legacy sessions have none — graceful absence.
    @Query
    private var allFeedback: [SetFeedback]

    @Query
    private var allHistory: [ExerciseHistory]

    @Query
    private var allPRs: [PersonalRecord]

    @Query
    private var allActivitySessions: [ActivitySession]

    @Query
    private var allDailySessions: [DailySession]

    @Environment(\.modelContext)
    private var modelContext

    @State
    private var expandedWorkoutID: UUID?

    /// Row currently swiped open (only one at a time).
    @State
    private var swipedWorkoutID: UUID?

    /// Pending hard-delete awaiting confirmation.
    @State
    private var pendingDelete: WorkoutPlan?

    // §20 — CSV import/export.
    @State
    private var showCSVImporter = false
    @State
    private var csvResultMessage: String?
    @State
    private var exportFileURL: URL?

    private var weightUnit: WeightUnit {
        userSettings.first?.weightUnit ?? .kg
    }

    private var feedbackBySetID: [UUID: SetFeedback] {
        Dictionary(allFeedback.map { ($0.setID, $0) }) { first, _ in first }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if completedWorkouts.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No Workouts Yet",
                    message: "Complete your first workout to see your history here."
                )
                .frame(minHeight: 400)
            } else {
                LazyVStack(spacing: TempoSpacing.sm) {
                    ForEach(completedWorkouts, id: \.id) { workout in
                        swipeToDeleteRow(workout)
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
            }
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Workout History")
        .navigationBarTitleDisplayMode(.inline)
        // §13 — cardio lives on its own surface; gym history stays this one.
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink(destination: RunHistoryView()) {
                    Image(systemName: "figure.run")
                }
            }
            // §20 — CSV import (Strong/Hevy/generic) + Strong-compatible export.
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showCSVImporter = true
                    } label: {
                        Label("Import CSV (Strong/Hevy)", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        exportHistory()
                    } label: {
                        Label("Export CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(completedWorkouts.isEmpty)
                } label: {
                    Image(systemName: "arrow.up.arrow.down.square")
                }
            }
        }
        .fileImporter(
            isPresented: $showCSVImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            importCSV(result)
        }
        .sheet(
            isPresented: Binding(
                get: { exportFileURL != nil },
                set: { if !$0 { exportFileURL = nil } }
            )
        ) {
            if let url = exportFileURL {
                ShareSheet(items: [url])
            }
        }
        .alert(
            "Workout Import",
            isPresented: Binding(
                get: { csvResultMessage != nil },
                set: { if !$0 { csvResultMessage = nil } }
            )
        ) {
            Button("OK") { csvResultMessage = nil }
        } message: {
            Text(csvResultMessage ?? "")
        }
        .alert(
            "Delete this workout?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { workout in
            Button("Delete Workout", role: .destructive) {
                deleteWorkout(workout)
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { workout in
            Text(deleteConfirmationMessage(workout))
        }
    }

    // MARK: - Swipe-to-Delete Row

    // LazyVStack can't use .swipeActions (List-only), and converting this
    // screen to a List would wreck the custom card design. So this is a
    // contained left-swipe: drag reveals a red Delete; tapping it asks for
    // confirmation (hard delete is irreversible — see deleteWorkout).

    private func swipeToDeleteRow(_ workout: WorkoutPlan) -> some View {
        let isSwiped = swipedWorkoutID == workout.id
        let revealWidth: CGFloat = 88

        return ZStack(alignment: .trailing) {
            // Delete affordance behind the card. It matches the card's
            // height because swiping force-collapses the row (below), so the
            // card is always the compact summary height when Delete shows —
            // it never stretches to the expanded detail height.
            Button {
                pendingDelete = workout
                HapticManager.notification(.warning)
            } label: {
                VStack(spacing: TempoSpacing.xxs) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Delete")
                        .font(.tempoCaption2)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Color.tempoTextInverse)
                .frame(width: revealWidth)
                .frame(maxHeight: .infinity)
                .background(Color.tempoError)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
            }

            workoutCard(workout)
                .offset(x: isSwiped ? -revealWidth - TempoSpacing.sm : 0)
                // highPriorityGesture so a horizontal swipe is claimed as a
                // swipe BEFORE the card's expand button registers a tap — the
                // old .gesture let a slightly-moving tap expand the row instead
                // of revealing Delete. A clean tap (no horizontal travel) still
                // falls through to the button and expands.
                .highPriorityGesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            // Only act on a predominantly HORIZONTAL drag, so a
                            // vertical scroll still scrolls the list.
                            guard abs(value.translation.width) > abs(value.translation.height) else {
                                return
                            }
                            withAnimation(.snappy(duration: 0.25)) {
                                if value.translation.width < -40 {
                                    if expandedWorkoutID == workout.id {
                                        expandedWorkoutID = nil
                                    }
                                    swipedWorkoutID = workout.id
                                } else if value.translation.width > 40 {
                                    swipedWorkoutID = nil
                                }
                            }
                        }
                )
        }
        .animation(.snappy(duration: 0.25), value: isSwiped)
    }

    /// Honest confirmation copy — states exactly what is and is NOT removed.
    /// Volume reads completed plans live, so it updates. ExerciseHistory /
    /// PRs are separate Exercise-linked records and are NOT rolled back.
    private func deleteConfirmationMessage(_ workout: WorkoutPlan) -> String {
        let setCount = workout.orderedExercises.reduce(0) { $0 + ($1.sets?.count ?? 0) }
        let name = workout.type.displayName
        return """
        \(name): permanently removes this session — its \(setCount) set\(setCount == 1 ? "" : "s"), \
        set feedback, and the progress-chart history & PRs it created. Weekly volume and charts \
        will update. This can't be undone.
        """
    }

    /// Hard delete. WorkoutPlan cascades to PlannedExercise → PlannedSet.
    /// SetFeedback links to PlannedSet with a .nullify rule, so it would be
    /// orphaned — we delete the linked feedback explicitly so "removes …
    /// feedback" in the confirmation is truthful.
    private func deleteWorkout(_ workout: WorkoutPlan) {
        // Full purge (user-chosen): the session AND every record it
        // produced, so it disappears from history, weekly volume, progress
        // charts and PRs alike.
        let cal = Calendar.current
        let sessionDay = cal.startOfDay(for: workout.finishedAt ?? workout.date)
        let exerciseIDs = Set(
            workout.orderedExercises.compactMap { $0.exercise?.id }
        )
        let setIDs = Set(
            workout.orderedExercises.flatMap { ($0.sets ?? []).map(\.id) }
        )

        // 1. Set feedback linked to this session's sets.
        for fb in allFeedback where setIDs.contains(fb.setID) {
            modelContext.delete(fb)
        }
        // 2. ExerciseHistory rows this session created (same day + one of
        //    this workout's exercises — saveWorkout stamps finishedAt).
        for h in allHistory
            where cal.isDate(h.date, inSameDayAs: sessionDay)
            && (h.exercise?.id).map(exerciseIDs.contains) == true {
            modelContext.delete(h)
        }
        // 3. PRs attributed to this exact plan.
        for pr in allPRs where pr.workoutPlanID == workout.id {
            modelContext.delete(pr)
        }
        // 3b. Non-gym ActivitySession produced by this plan (football etc.).
        //     Keyed by exact workoutPlanID — without this, deleting a football
        //     session from history would orphan its ActivitySession record.
        for session in allActivitySessions where session.workoutPlanID == workout.id {
            modelContext.delete(session)
        }
        // 3c. The brain's DailySession for this day. Its `workoutPlan` link is a
        //     one-way `.nullify` with NO inverse, so deleting the plan (step 4)
        //     would leave this session pointing at dangling backing — later read
        //     in sessionRPEAccuracy → crash. Matched by DAY (never by traversing
        //     `.workoutPlan`, which could itself already be dangling); the §8
        //     model is write-once one-session-per-day, so the day is the key.
        for s in allDailySessions where cal.isDate(s.date, inSameDayAs: sessionDay) {
            modelContext.delete(s)
        }
        // 4. The plan itself (cascades to PlannedExercise → PlannedSet).
        modelContext.delete(workout)
        try? modelContext.save()

        swipedWorkoutID = nil
        pendingDelete = nil
        HapticManager.notification(.success)
    }

    // MARK: - CSV Import / Export (§20)

    private func importCSV(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                csvResultMessage = "Couldn't read that file."
                return
            }
            do {
                let summary = try WorkoutCSVService.importCSV(text, modelContext: modelContext)
                csvResultMessage = summary.label
                if summary.workouts > 0 {
                    NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
                    HapticManager.notification(.success)
                }
            } catch {
                csvResultMessage = error.localizedDescription
            }
        case let .failure(error):
            csvResultMessage = error.localizedDescription
        }
    }

    private func exportHistory() {
        let csv = WorkoutCSVService.exportCSV(plans: completedWorkouts)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tempo-workout-history.csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportFileURL = url
        } catch {
            csvResultMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Workout Card

    private func workoutCard(_ workout: WorkoutPlan) -> some View {
        let isExpanded = expandedWorkoutID == workout.id

        return VStack(spacing: 0) {
            // Main card content
            Button {
                // If this row is swiped open, a tap closes the swipe
                // (iOS-standard) rather than expanding — which also keeps
                // the Delete affordance from ever pairing with an expanded
                // (tall) card.
                if swipedWorkoutID == workout.id {
                    withAnimation(.snappy(duration: 0.25)) {
                        swipedWorkoutID = nil
                    }
                    return
                }
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedWorkoutID = isExpanded ? nil : workout.id
                }
                HapticManager.selection()
            } label: {
                VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                    // Row 1: Date + workout type
                    HStack {
                        Text(workout.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)

                        Spacer()

                        Text(workout.type.displayName.uppercased())
                            .font(.tempoCaption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.tempoSignal)
                            .padding(.horizontal, TempoSpacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.tempoSignal.opacity(0.12))
                            .clipShape(Capsule())
                    }

                    // Row 2: Stats
                    HStack(spacing: TempoSpacing.md) {
                        // Duration
                        if let duration = workout.durationMinutes ?? workout.actualDurationMinutes {
                            HStack(spacing: TempoSpacing.xxs) {
                                Image(systemName: "timer")
                                    .font(.system(size: 11))
                                Text("\(duration) min")
                                    .font(.tempoCaption1)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .foregroundStyle(Color.tempoTextSecondary)
                        }

                        // Exercise count — keep on one line (don't let "6
                        // exercises" wrap to a second row).
                        let exerciseCount = workout.orderedExercises.count
                        if exerciseCount > 0 {
                            HStack(spacing: TempoSpacing.xxs) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .font(.system(size: 11))
                                Text("\(exerciseCount) exercises")
                                    .font(.tempoCaption1)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .foregroundStyle(Color.tempoTextSecondary)
                        }

                        // Total volume
                        let vol = workout.totalVolume
                        if vol > 0 {
                            HStack(spacing: TempoSpacing.xxs) {
                                Image(systemName: "scalemass")
                                    .font(.system(size: 11))
                                Text(formatVolume(vol))
                                    .font(.tempoCaption1)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .foregroundStyle(Color.tempoTextSecondary)
                        }

                        // Warm-up completed marker
                        if workout.warmupCompleted {
                            HStack(spacing: TempoSpacing.xxs) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 11))
                                Text("Warm-up")
                                    .font(.tempoCaption1)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .foregroundStyle(Color.tempoRecoveryGreen)
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .padding(TempoSpacing.cardPadding)
            }
            .buttonStyle(.plain)

            // Expanded exercise detail
            if isExpanded {
                Divider()
                    .background(Color.tempoTextTertiary.opacity(0.2))

                if let notes = workout.userNotes {
                    Text(notes)
                        .font(.tempoCaption1)
                        .italic()
                        .foregroundStyle(Color.tempoTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TempoSpacing.cardPadding)
                        .padding(.top, TempoSpacing.sm)
                }

                Group {
                    if workout.orderedExercises.isEmpty,
                       let session = activitySession(for: workout) {
                        // Non-gym session (football etc.) — no exercises to
                        // list; show the Whoop activity detail instead.
                        activityDetail(session)
                    } else {
                        VStack(spacing: TempoSpacing.xs) {
                            ForEach(workout.orderedExercises, id: \.id) { plannedEx in
                                exerciseDetailRow(plannedEx)
                            }
                        }
                    }
                }
                .padding(.horizontal, TempoSpacing.cardPadding)
                .padding(.vertical, TempoSpacing.sm)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
    }

    // MARK: - Activity (non-gym) Detail

    private func activitySession(for workout: WorkoutPlan) -> ActivitySession? {
        allActivitySessions.first { $0.workoutPlanID == workout.id }
    }

    @ViewBuilder
    private func activityDetail(_ session: ActivitySession) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(spacing: TempoSpacing.lg) {
                if let strain = session.strain {
                    activityMetric(String(format: "%.1f", strain), "Strain")
                }
                if let mins = session.durationMinutes {
                    activityMetric("\(Int(mins))m", "Duration")
                }
                if let hr = session.averageHeartRate {
                    activityMetric("\(Int(hr))", "Avg HR")
                }
                if let cal = session.caloriesBurned {
                    activityMetric("\(Int(cal))", "Cal")
                }
            }

            if let range = HydrationMath.sweatLossLitres(
                caloriesBurned: session.caloriesBurned,
                durationMinutes: session.durationMinutes
            ) {
                HStack(spacing: TempoSpacing.xs) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.tempoElectric)
                    Text(String(format: "~%.1f–%.1f L lost", range.lowerBound, range.upperBound))
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }

            if session.source == "manual" {
                Text("Logged manually — no Whoop data.")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(label)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    // MARK: - Exercise Detail Row

    private func exerciseDetailRow(_ plannedEx: PlannedExercise) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            HStack {
                Text(plannedEx.exercise?.name ?? "Exercise")
                    .font(.tempoBody)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .lineLimit(1)

                Spacer()

                // Completion indicator
                Image(systemName: plannedEx.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(
                        plannedEx.isComplete ? Color.tempoRecoveryGreen : Color.tempoTextTertiary
                    )
            }

            // Sets detail — per-set chip + optional feedback line
            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                ForEach(plannedEx.orderedSets, id: \.id) { set in
                    HStack(spacing: TempoSpacing.xs) {
                        if set.isWarmup {
                            // Warm-up / ramp set — show the ramp target (not the
                            // blank "--" it was before), tagged and lighter.
                            let w = set.actualWeight ?? set.targetWeight ?? 0
                            let r = set.actualReps ?? set.targetReps
                            let dispW = WeightUnit.kg.convert(w, to: weightUnit)
                            Text("\(Int(dispW))x\(r)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.tempoTextTertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.tempoBgSecondary.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xs, style: .continuous))
                            Text("Warm-up")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        } else if set.completed, let weight = set.actualWeight, let reps = set.actualReps {
                            let dispW = WeightUnit.kg.convert(weight, to: weightUnit)
                            Text("\(Int(dispW))x\(reps)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.tempoTextSecondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.tempoBgSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xs, style: .continuous))
                        } else {
                            Text("--")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color.tempoTextTertiary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.tempoBgSecondary.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xs, style: .continuous))
                        }

                        // Feedback line — only for working sets with a linked
                        // SetFeedback. Warm-ups have none.
                        if !set.isWarmup, let fb = feedbackBySetID[set.id] {
                            Text("RPE \(fb.rpe) · \(fb.breathDifficulty.displayName) · \(fb.formQuality.displayName)")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }

            // Volume for this exercise
            let vol = plannedEx.totalVolume
            if vol > 0 {
                Text("Volume: \(formatVolume(vol))")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(.vertical, TempoSpacing.xxs)
    }

    // MARK: - Helpers

    /// Formats a kg volume into the user's preferred unit.
    private func formatVolume(_ volumeKg: Double) -> String {
        let v = WeightUnit.kg.convert(volumeKg, to: weightUnit)
        let unit = weightUnit.abbreviation
        if v >= 1000 {
            return String(format: "%.1fk %@", v / 1000, unit)
        }
        return "\(Int(v)) \(unit)"
    }
}
