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

    /// Bodyweight for imported pull-up / dip rows (effective load = bodyweight + added).
    @Query
    private var profiles: [UserProfile]

    /// All captured set feedback. Bounded (one row per logged set); built
    /// into a `[setID: SetFeedback]` lookup so expanded rows can show
    /// RPE/breath/form. Legacy sessions have none — graceful absence.
    @Query
    private var allFeedback: [SetFeedback]

    @Query
    private var allHistory: [ExerciseHistory]

    @Query
    private var allPRs: [PersonalRecord]

    /// §13 — measurement-spine prediction ledger; a deleted workout's rows
    /// must go with it or they're orphaned forever (Step 2's accuracy metric
    /// would keep scoring a session that no longer exists).
    @Query
    private var allPredictionLogs: [PredictionLog]

    @Query
    private var allActivitySessions: [ActivitySession]

    @Query
    private var allDailySessions: [DailySession]

    /// Fix #7 — conditioning block results (shuttle times, duration/distance,
    /// rounds, RPE), grouped under the day's entry by `programSessionKey`.
    @Query
    private var allConditioningResults: [ConditioningBlockResult]

    @Query
    private var allTrainerPrograms: [TrainerProgram]

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

    /// §20 — CSV import/export.
    @State
    private var showCSVImporter = false
    @State
    private var csvResultMessage: String?
    @State
    private var exportFileURL: URL?
    /// A parsed file waiting for the athlete to say which unit its weights
    /// are in (Strong's older exports don't say).
    @State
    private var pendingUnitChoice: WorkoutCSVService.ParsedFile?
    /// Batch id of the most recent import — lets the result alert and the
    /// menu remove the whole import in one tap.
    @AppStorage("lastWorkoutImportBatchID")
    private var lastImportBatchID = ""
    @State
    private var showUndoImportConfirm = false
    /// Non-nil while a CSV is being read / written: the stage label and, once
    /// writing starts, 0...1 progress (nil = still reading, indeterminate).
    @State
    private var importStage: String?
    @State
    private var importProgress: Double?
    /// True only while the alert shows a fresh import result.
    @State
    private var resultOffersUndo = false

    /// The most recent import, only while some of its workouts still exist.
    private var undoableImportBatch: UUID? {
        guard let id = UUID(uuidString: lastImportBatchID),
              completedWorkouts.contains(where: { $0.importBatchID == id })
        else {
            return nil
        }
        return id
    }

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
                LazyVStack(spacing: Tide.s2) {
                    ForEach(completedWorkouts, id: \.id) { workout in
                        swipeToDeleteRow(workout)
                    }
                }
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, (Tide.s10 + Tide.s2) + (Tide.s10 + Tide.s2))
            }
        }
        .tidePage()
        #if DEBUG
        // Sim check: `-debugCSVImportPath /path/file.csv` runs the same import
        // path as the file picker (parse off-main, unit prompt, progress).
        .task {
            if let path = UserDefaults.standard.string(forKey: "debugCSVImportPath"), !path.isEmpty {
                importCSV(.success(URL(fileURLWithPath: path)))
            }
        }
        #endif
        .overlay {
            if let importStage {
                importOverlay(importStage)
            }
        }
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
                    if undoableImportBatch != nil {
                        Button(role: .destructive) {
                            showUndoImportConfirm = true
                        } label: {
                            Label("Undo last import", systemImage: "arrow.uturn.backward")
                        }
                    }
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
                set: {
                    if !$0 {
                        exportFileURL = nil
                    }
                }
            )
        ) {
            if let url = exportFileURL {
                ShareSheet(items: [url])
            }
        }
        .confirmationDialog(
            "Which unit is this file in?",
            isPresented: Binding(
                get: { pendingUnitChoice != nil },
                set: {
                    if !$0 {
                        pendingUnitChoice = nil
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            // The athlete's own unit first — the likeliest answer.
            ForEach([weightUnit, weightUnit == .kg ? WeightUnit.lbs : .kg], id: \.self) { unit in
                Button(unit == .kg ? "Kilograms (kg)" : "Pounds (lbs)") {
                    if let file = pendingUnitChoice {
                        pendingUnitChoice = nil
                        startImport(file, unit: unit)
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingUnitChoice = nil }
        } message: {
            Text("This export doesn't say. Picking the wrong one makes every weight 2.2x off. Tempo is set to \(weightUnit.abbreviation).")
        }
        .alert(
            "Workout Import",
            isPresented: Binding(
                get: { csvResultMessage != nil },
                set: {
                    if !$0 {
                        csvResultMessage = nil
                        resultOffersUndo = false
                    }
                }
            )
        ) {
            Button(resultOffersUndo ? "Keep" : "OK") { csvResultMessage = nil }
            if resultOffersUndo, undoableImportBatch != nil {
                Button("Undo import", role: .destructive) { undoLastImport() }
            }
        } message: {
            Text(csvResultMessage ?? "")
        }
        .alert("Undo last import?", isPresented: $showUndoImportConfirm) {
            Button("Undo import", role: .destructive) { undoLastImport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes every workout, record and new exercise that import added. Workouts you logged yourself stay.")
        }
        .alert(
            "Delete this workout?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: {
                    if !$0 {
                        pendingDelete = nil
                    }
                }
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
            Text(Self.deleteConfirmationMessage(workout))
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
                VStack(spacing: Tide.hair) {
                    Image(systemName: "trash.fill")
                        .font(Tide.bodyStrong)
                    Text("Delete")
                        .font(Tide.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Tide.ink)
                .frame(width: revealWidth)
                .frame(maxHeight: .infinity)
                .background(Tide.danger)
                .clipShape(RoundedRectangle(cornerRadius: Tide.cardRadius, style: .continuous))
            }
            // The cards are glass now: the red must not show through until
            // the row is swiped open.
            .opacity(isSwiped ? 1 : 0)
            .allowsHitTesting(isSwiped)
            .accessibilityHidden(!isSwiped)

            workoutCard(workout)
                .offset(x: isSwiped ? -revealWidth - Tide.s2 : 0)
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
                            withAnimation(Tide.snap) {
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
        .animation(Tide.snap, value: isSwiped)
    }

    /// Honest confirmation copy — states exactly what is and is NOT removed.
    /// Volume reads completed plans live, so it updates. ExerciseHistory / PRs
    /// this session produced ARE deleted with it (§13) — matched by
    /// `workoutPlanID`, not merely nulled elsewhere.
    /// Counts the sets actually logged — not the planned ones (a session
    /// ended after 2 of 17 sets used to say "its 17 sets").
    static func deleteConfirmationMessage(_ workout: WorkoutPlan) -> String {
        let setCount = workout.orderedExercises.reduce(0) { total, ex in
            total + (ex.sets ?? []).filter { $0.completed && !$0.isWarmup }.count
        }
        let name = workout.type.displayName
        return """
        \(name): permanently removes this session — its \(setCount) logged set\(setCount == 1 ? "" : "s"), \
        set feedback, pain flags, and the progress-chart history & PRs it created. Weekly volume and charts \
        will update. Weight adjustments Tempo already learned from it stay. This can't be undone.
        """
    }

    /// See `WorkoutPurge.historyRowsToDelete` (kept as a forwarder for the
    /// §13 tests that pin it here).
    static func historyRowsToDelete(
        for workout: WorkoutPlan,
        allHistory: [ExerciseHistory],
        calendar: Calendar = .current
    ) -> [ExerciseHistory] {
        WorkoutPurge.historyRowsToDelete(for: workout, allHistory: allHistory, calendar: calendar)
    }

    /// Full purge — see `WorkoutPurge.purge` (also notifies Today/Dashboard,
    /// so a deleted TODAY workout doesn't linger on those screens).
    private func deleteWorkout(_ workout: WorkoutPlan) {
        WorkoutPurge.purge(workout, modelContext: modelContext)
        swipedWorkoutID = nil
        pendingDelete = nil
        HapticManager.notification(.success)
    }

    // MARK: - CSV Import / Export (§20)

    private func importCSV(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            importStage = "Reading file…"
            importProgress = nil
            // Reading + parsing a multi-year export is heavy: off the main actor.
            Task {
                let parsed = await Task.detached(priority: .userInitiated) { () -> Result<WorkoutCSVService.ParsedFile, any Error> in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer {
                        if scoped {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    guard let text = WorkoutCSVService.readText(from: url) else {
                        return .failure(CSVReadError())
                    }
                    return Result { try WorkoutCSVService.parse(text) }
                }.value
                switch parsed {
                case let .success(file):
                    if file.declaredUnit != nil || !file.sets.contains(where: { ($0.weight ?? 0) > 0 }) {
                        await runImport(file, unit: file.declaredUnit ?? weightUnit)
                    } else {
                        importStage = nil
                        pendingUnitChoice = file
                    }
                case let .failure(error):
                    importStage = nil
                    resultOffersUndo = false
                    csvResultMessage = error.localizedDescription
                }
            }
        case let .failure(error):
            csvResultMessage = error.localizedDescription
        }
    }

    private struct CSVReadError: LocalizedError {
        var errorDescription: String? {
            "Couldn't read that file."
        }
    }

    private func startImport(_ file: WorkoutCSVService.ParsedFile, unit: WeightUnit) {
        Task { await runImport(file, unit: unit) }
    }

    @MainActor
    private func runImport(_ file: WorkoutCSVService.ParsedFile, unit: WeightUnit) async {
        importStage = "Importing workouts…"
        importProgress = 0
        defer {
            importStage = nil
            importProgress = nil
        }
        do {
            let summary = try await WorkoutCSVService.importParsed(
                file,
                assumedUnit: unit,
                bodyweightKg: profiles.first?.weightKg,
                modelContext: modelContext,
                progress: { importProgress = $0 },
                // Stored BEFORE the first workout is written: the context
                // autosaves in the background, so a kill mid-import can leave
                // a partial batch that "Undo last import" must still cover.
                willInsert: { lastImportBatchID = $0.uuidString }
            )
            csvResultMessage = summary.label
            resultOffersUndo = summary.workouts > 0
            if summary.workouts > 0 {
                lastImportBatchID = summary.batchID?.uuidString ?? ""
                NotificationCenter.default.post(name: .tempoWorkoutChanged, object: nil)
                HapticManager.notification(.success)
            }
        } catch {
            resultOffersUndo = false
            csvResultMessage = error.localizedDescription
        }
    }

    private func importOverlay(_ stage: String) -> some View {
        ZStack {
            Tide.ink.opacity(0.55).ignoresSafeArea()
            VStack(spacing: Tide.s3) {
                if let importProgress {
                    ProgressView(value: importProgress)
                        .tint(Color.accentColor)
                        .frame(width: 180)
                } else {
                    ProgressView()
                }
                Text(importProgress.map { "\(stage) \(Int($0 * 100))%" } ?? stage)
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
            }
            .padding(Tide.s5)
            .background(Tide.fill, in: .rect(cornerRadius: Tide.cardRadius))
        }
        .transition(.opacity)
    }

    private func undoLastImport() {
        csvResultMessage = nil
        resultOffersUndo = false
        guard let batch = undoableImportBatch else {
            return
        }
        do {
            let removed = try WorkoutCSVService.undoImport(batchID: batch, modelContext: modelContext)
            lastImportBatchID = ""
            csvResultMessage = "Import undone — \(removed) workouts removed."
            HapticManager.notification(.success)
        } catch {
            csvResultMessage = "Couldn't undo the import: \(error.localizedDescription)"
        }
    }

    private func exportHistory() {
        let csv = WorkoutCSVService.exportCSV(plans: completedWorkouts, unit: weightUnit)
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
                    withAnimation(Tide.snap) {
                        swipedWorkoutID = nil
                    }
                    return
                }
                withAnimation(Tide.snap) {
                    expandedWorkoutID = isExpanded ? nil : workout.id
                }
                HapticManager.selection()
            } label: {
                VStack(alignment: .leading, spacing: Tide.s2) {
                    // Row 1: workout type + date
                    HStack(alignment: .firstTextBaseline) {
                        Text(workout.type.displayName)
                            .font(Tide.headline)
                            .foregroundStyle(Tide.text)

                        Spacer()

                        Text(workout.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    }

                    // Row 2: Stats
                    HStack(spacing: Tide.s3) {
                        // Duration
                        if let durationText = Self.durationText(for: workout) {
                            HStack(spacing: Tide.hair) {
                                Image(systemName: "timer")
                                    .font(Tide.label)
                                Text(durationText)
                                    .font(Tide.caption)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .foregroundStyle(Tide.text2)
                        }

                        // Exercise count — keep on one line (don't let "6
                        // exercises" wrap to a second row).
                        let exerciseCount = workout.status == .completed
                            ? workout.performedExerciseCount : workout.orderedExercises.count
                        if exerciseCount > 0 {
                            HStack(spacing: Tide.hair) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .font(Tide.label)
                                Text("\(exerciseCount) \(exerciseCount == 1 ? "exercise" : "exercises")")
                                    .font(Tide.caption)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .foregroundStyle(Tide.text2)
                        }

                        // Total volume
                        let vol = workout.totalVolume
                        if vol > 0 {
                            HStack(spacing: Tide.hair) {
                                Image(systemName: "scalemass")
                                    .font(Tide.label)
                                Text(formatVolume(vol))
                                    .font(Tide.caption)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .foregroundStyle(Tide.text2)
                        }

                        // Warm-up completed marker
                        if workout.warmupCompleted {
                            HStack(spacing: Tide.hair) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(Tide.label)
                                Text("Warm-up")
                                    .font(Tide.caption)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .foregroundStyle(TideTrain.positive)
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(Tide.label)
                            .foregroundStyle(Tide.text3)
                    }
                }
                .padding(Tide.s4)
            }
            .buttonStyle(.plain)

            // Expanded exercise detail
            if isExpanded {
                Divider()
                    .background(Tide.text3.opacity(0.2))

                if let notes = workout.userNotes {
                    Text(notes)
                        .font(Tide.caption)
                        .italic()
                        .foregroundStyle(Tide.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Tide.s4)
                        .padding(.top, Tide.s2)
                }

                Group {
                    if workout.orderedExercises.isEmpty,
                       let session = activitySession(for: workout)
                    {
                        // Non-gym session (football etc.) — no exercises to
                        // list; show the Whoop activity detail instead.
                        activityDetail(session)
                    } else {
                        VStack(spacing: Tide.s1) {
                            ForEach(workout.orderedExercises, id: \.id) { plannedEx in
                                exerciseDetailRow(plannedEx)
                            }
                        }
                    }
                }
                .padding(.horizontal, Tide.s4)
                .padding(.vertical, Tide.s2)
                .transition(.opacity.combined(with: .move(edge: .top)))

                // Fix #7 — trainer-program conditioning blocks logged for this
                // day (grouped by session — a two-a-day can carry both a lift
                // and a conditioning second session).
                conditioningResultsSection(workout)
                    .padding(.horizontal, Tide.s4)
                    .padding(.bottom, Tide.s2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassEffect(.regular.tint(Tide.glassCard), in: .rect(cornerRadius: Tide.cardRadius))
    }

    // MARK: - Activity (non-gym) Detail

    private func activitySession(for workout: WorkoutPlan) -> ActivitySession? {
        allActivitySessions.first { $0.workoutPlanID == workout.id }
    }

    /// A finished session's measured time wins over the planned figure; under a
    /// minute reads "<1 min", otherwise the nearest minute.
    static func durationText(for workout: WorkoutPlan) -> String? {
        if let seconds = workout.actualDurationSeconds {
            return WorkoutPlan.durationLabel(seconds: seconds)
        }
        return workout.durationMinutes.map { "\($0) min" }
    }

    /// Working sets always (logged or not), warm-ups only when actually done.
    static func visibleSets(of plannedEx: PlannedExercise) -> [PlannedSet] {
        plannedEx.orderedSets.filter { !$0.isWarmup || $0.completed }
    }

    private func activityDetail(_ session: ActivitySession) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(spacing: Tide.s4) {
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
                HStack(spacing: Tide.s1) {
                    Image(systemName: "drop.fill")
                        .font(Tide.label)
                        .foregroundStyle(Tide.water)
                    Text(String(format: "~%.1f–%.1f L lost", range.lowerBound, range.upperBound))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
            }

            if session.source == "manual" {
                Text("Logged manually — no Whoop data.")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func activityMetric(_ value: String, _ label: String) -> some View {
        VStack(spacing: Tide.hair) {
            Text(value)
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
            Text(label)
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
        }
    }

    // MARK: - Conditioning Block Results (Fix #7)

    private func conditioningResults(for workout: WorkoutPlan) -> [ConditioningBlockResult] {
        allConditioningResults.filter { $0.workoutPlanID == workout.id }
    }

    /// Resolve a `programSessionKey` back to its `ProgramDay` (title, blocks)
    /// so the grouping can show a heading and block names, not just raw
    /// numbers. nil when the program was since deleted/re-imported — the
    /// results still render, just without a heading/block name.
    private func programDay(forSessionKey key: String) -> ProgramDay? {
        guard let programID = key.split(separator: "#").first.flatMap({ UUID(uuidString: String($0)) }),
              let program = allTrainerPrograms.first(where: { $0.id == programID })
        else {
            return nil
        }
        return program.day(forSessionKey: key)
    }

    @ViewBuilder
    private func conditioningResultsSection(_ workout: WorkoutPlan) -> some View {
        let results = conditioningResults(for: workout)
        if !results.isEmpty {
            let grouped = Dictionary(grouping: results) { $0.programSessionKey ?? "" }
            VStack(alignment: .leading, spacing: Tide.s2) {
                Divider()
                    .background(Tide.text3.opacity(0.2))
                ForEach(grouped.keys.sorted(), id: \.self) { key in
                    let day = programDay(forSessionKey: key)
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(day?.title ?? day?.workoutType.displayName ?? "Conditioning").tideLabel()
                        ForEach((grouped[key] ?? []).sorted { $0.createdAt < $1.createdAt }, id: \.id) { result in
                            conditioningResultRow(result, day: day)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Tide.s2)
        }
    }

    private func conditioningResultRow(_ result: ConditioningBlockResult, day: ProgramDay?) -> some View {
        let block = day?.exercises.first { $0.id == result.blockID }
        return HStack(alignment: .top, spacing: Tide.s1) {
            Image(systemName: conditioningResultIcon(result))
                .font(Tide.label)
                .foregroundStyle(conditioningResultColor(result))
                .padding(.top, Tide.hair)
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text(block?.name ?? "Block")
                    .font(Tide.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Tide.text)
                Text(conditioningResultSummary(result))
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text2)
                if let notes = result.notes, !notes.isEmpty {
                    Text(notes)
                        .font(Tide.caption)
                        .italic()
                        .foregroundStyle(Tide.text3)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func conditioningResultIcon(_ result: ConditioningBlockResult) -> String {
        switch result.targetMet {
        case true: "checkmark.circle.fill"
        case false: "xmark.circle.fill"
        case nil: "checkmark.seal.fill"
        }
    }

    private func conditioningResultColor(_ result: ConditioningBlockResult) -> Color {
        switch result.targetMet {
        case true: TideTrain.positive
        case false: Tide.danger
        case nil: Tide.text3
        }
    }

    private func conditioningResultSummary(_ result: ConditioningBlockResult) -> String {
        var parts: [String] = []
        if let times = result.repTimesSeconds, !times.isEmpty {
            parts.append("\(times.count) rep\(times.count == 1 ? "" : "s")")
            if let best = ConditioningTargetEvaluator.bestTime(times) {
                parts.append("best \(formatConditioningSeconds(best))")
            }
        }
        if let duration = result.durationSeconds {
            parts.append("\(Int((duration / 60).rounded()))'")
        }
        if let distance = result.distanceMeters {
            parts.append(String(format: "%.1f km", distance / 1000))
        }
        if let rounds = result.roundsCompleted {
            parts.append("\(rounds) rounds")
        }
        if let rpe = result.rpe {
            parts.append("RPE \(rpe.formatted(.number.precision(.fractionLength(0 ... 1))))")
        }
        return parts.isEmpty ? "Logged" : parts.joined(separator: " · ")
    }

    private func formatConditioningSeconds(_ seconds: Double) -> String {
        seconds >= 60
            ? String(format: "%d:%02d\"", Int(seconds) / 60, Int(seconds) % 60)
            : "\(Int(seconds))\""
    }

    // MARK: - Exercise Detail Row

    private func exerciseDetailRow(_ plannedEx: PlannedExercise) -> some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            HStack {
                Text(plannedEx.displayName)
                    .font(Tide.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Tide.text)
                    .lineLimit(1)

                Spacer()

                // Completion indicator
                Image(systemName: plannedEx.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(Tide.caption)
                    .foregroundStyle(
                        plannedEx.isComplete ? TideTrain.positive : Tide.text3
                    )
            }

            let isBodyweight = plannedEx.exercise.map { StrengthStandards.isBodyweightLoaded($0.equipment) } ?? false
            // Sets detail — per-set chip + optional feedback line
            VStack(alignment: .leading, spacing: Tide.hair) {
                // H — a planned ramp the athlete never did isn't history.
                ForEach(Self.visibleSets(of: plannedEx), id: \.id) { set in
                    HStack(spacing: Tide.s1) {
                        if set.isWarmup {
                            // Warm-up / ramp set — show the ramp target (not the
                            // blank "--" it was before), tagged and lighter.
                            let w = set.actualWeight ?? set.targetWeight ?? 0
                            let r = set.actualReps ?? set.targetReps
                            // Fix #9 — a per-side ramp target reads "x8/side".
                            Text("\(WeightFormat.compactSetLoad(kg: w, addedKg: set.addedLoadKg, bodyweight: isBodyweight, unit: weightUnit))x\(SideRepsFormat.reps(r, perSide: plannedEx.perSide))")
                                .font(Tide.label.monospacedDigit())
                                .foregroundStyle(Tide.text3)
                                .padding(.horizontal, 4)
                                .padding(.vertical, Tide.hair)
                                .background(Tide.fill.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: Tide.s1, style: .continuous))
                            // §13 — every warmup on a trainer day is one
                            // Tempo added; the trainer never wrote it.
                            Text(plannedEx.workoutPlan?.programSessionKey != nil ? "Tempo warm-up" : "Warm-up")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text3)
                        } else if set.completed, let weight = set.actualWeight, let reps = set.actualReps {
                            // Fix #9 — "x8/side", or "xL8/R7" when the
                            // athlete logged an uneven L/R split.
                            let repsText = SideRepsFormat.loggedReps(
                                actual: reps, left: set.actualRepsLeft, right: set.actualRepsRight,
                                perSide: plannedEx.perSide
                            )
                            Text("\(WeightFormat.compactSetLoad(kg: weight, addedKg: set.addedLoadKg, bodyweight: isBodyweight, unit: weightUnit))x\(repsText)")
                                .font(Tide.label.monospacedDigit())
                                .foregroundStyle(Tide.text2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, Tide.hair)
                                .background(Tide.fill, in: .rect(cornerRadius: Tide.s1))
                        } else {
                            Text("--")
                                .font(Tide.label.monospacedDigit())
                                .foregroundStyle(Tide.text3)
                                .padding(.horizontal, 4)
                                .padding(.vertical, Tide.hair)
                                .background(Tide.fill.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: Tide.s1, style: .continuous))
                        }

                        // Feedback line — only for working sets with a linked
                        // SetFeedback. Warm-ups have none.
                        // Only what the athlete entered — untouched defaults
                        // used to read as "RPE 7 · Moderate · Clean" on every set.
                        if !set.isWarmup, let summary = feedbackBySetID[set.id]?.enteredSummary {
                            Text(summary)
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text3)
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
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
        }
        .padding(.vertical, Tide.hair)
    }

    // MARK: - Helpers

    /// Formats a kg volume into the user's preferred unit.
    private func formatVolume(_ volumeKg: Double) -> String {
        WeightFormat.volumeText(kg: volumeKg, unit: weightUnit)
    }
}
