//
// TrainerReportSheet.swift
// Tempo
//
// Fix #8 — "send report to trainer": pick a scope (this week / whole
// program) and a language (Italiano/English), preview the summary, then
// share the SAME `TrainerReportDocument` as WhatsApp-ready text or an A4
// PDF (`TrainerReportBuilder` / `TrainerReportTextFormatter` /
// `TrainerReportPDFRenderer`).
//
// Entry points: a toolbar button on `TrainerProgramView` (program-level —
// covers whichever program is active) and an optional one on
// `WorkoutSummaryView` right after a trainer session (session-level —
// resolves its program via `TrainerReportSheet.program(forSessionKey:)`).
//

import SwiftData
import SwiftUI

// MARK: - TrainerReportSheet

struct TrainerReportSheet: View {
    let program: TrainerProgram
    /// Sunday wrap-up feature — fires when the athlete taps either share
    /// button, so an embedding flow (`SundayWrapUpSheet`) can remember the
    /// report was actually sent this week. nil (default) for every other
    /// entry point — behavior is unchanged for them.
    var onShared: (() -> Void)?
    /// Sunday wrap-up feature — true when this view is embedded as a STEP
    /// inside another modal (`SundayWrapUpSheet`) rather than presented as
    /// its own `.sheet`. Suppresses the toolbar "Close" button: with this
    /// view embedded (not its own sheet), `@Environment(\.dismiss)` resolves
    /// to the OUTER sheet's dismiss — tapping "Close" here would silently
    /// skip the wrap-up's remaining steps instead of just leaving this one.
    /// The embedding flow supplies its own Skip/Continue navigation instead.
    var embedded = false

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    /// Whoop-football feature — best-effort async fallback (see
    /// `enrichFootballWithWhoopIfNeeded`) when a football match/day has no
    /// already-persisted `ActivitySession`. Same container every other
    /// Training screen reads (`TrainerProgramView`, `TodayWorkoutView`).
    @Environment(ServiceContainer.self)
    private var services

    @State
    private var scope: TrainerReportScope = .week
    @State
    private var language: TrainerReportLanguage
    @State
    private var document: TrainerReportDocument?
    @State
    private var pdfShareURL: URL?
    @State
    private var pdfErrorMessage: String?
    /// Whoop-football feature — tracks the in-flight enrichment fetch so a
    /// scope/language change (new `rebuild()`) cancels the stale one instead
    /// of racing it into `document`.
    @State
    private var footballEnrichmentTask: Task<Void, Never>?

    init(program: TrainerProgram, onShared: (() -> Void)? = nil, embedded: Bool = false) {
        self.program = program
        self.onShared = onShared
        self.embedded = embedded
        _language = State(initialValue: TrainerReportBuilder.detectLanguage(program: program))
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                    Picker("Scope", selection: $scope) {
                        Text("This Week").tag(TrainerReportScope.week)
                        Text("Whole Program").tag(TrainerReportScope.wholeProgram)
                    }
                    .pickerStyle(.segmented)

                    Picker("Language", selection: $language) {
                        ForEach(TrainerReportLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)

                    if let document {
                        previewSection(document)
                        shareButtons(document)
                    }
                }
                .padding(.horizontal, TempoSpacing.screenEdge)
                .padding(.top, TempoSpacing.lg)
                .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Report to Trainer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .alert(
                "Couldn't build the PDF",
                isPresented: Binding(get: { pdfErrorMessage != nil }, set: {
                    if !$0 {
                        pdfErrorMessage = nil
                    }
                })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(pdfErrorMessage ?? "")
            }
        }
        .onAppear { rebuild() }
        .onChange(of: scope) { _, _ in rebuild() }
        .onChange(of: language) { _, _ in rebuild() }
    }

    // MARK: - Preview

    private func previewSection(_ document: TrainerReportDocument) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text(document.title)
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(document.dateRangeLabel)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)

            VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                ForEach(Array(document.summaryLines.enumerated()), id: \.offset) { _, line in
                    Text("• \(line)")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
            }
            .padding(TempoSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg))

            if document.sessions.isEmpty {
                Text(document.strings.noSessionsText)
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            } else {
                ForEach(document.sessions) { session in
                    HStack(spacing: TempoSpacing.xs) {
                        Text(session.dateLabel)
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                        Text(session.title)
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(session.statusLabel)
                            .font(.tempoCaption2.weight(.semibold))
                            .foregroundStyle(statusColor(session.status))
                    }
                }
            }

            // Pause/travel-pain feature — football/pain/pauses/travel-swap
            // sections. See TrainerReportSupplementalSections.swift.
            ForEach(document.extraSections) { section in
                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    Text(section.title.uppercased())
                        .font(.tempoCaption2.weight(.semibold))
                        .foregroundStyle(Color.tempoTextTertiary)
                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                        Text("• \(line)")
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextSecondary)
                    }
                }
                .padding(.top, TempoSpacing.xs)
            }
        }
    }

    private func statusColor(_ status: TrainerReportSessionStatus) -> Color {
        switch status {
        case .done: Color.tempoRecoveryGreen
        case .missed: Color.tempoError
        case .moved: Color.tempoWarning
        }
    }

    // MARK: - Share

    private func shareButtons(_ document: TrainerReportDocument) -> some View {
        VStack(spacing: TempoSpacing.sm) {
            ShareLink(item: TrainerReportTextFormatter.text(for: document)) {
                Label("Share as Text", systemImage: "message")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoSecondary)
            .simultaneousGesture(TapGesture().onEnded { onShared?() })

            if let pdfShareURL {
                ShareLink(item: pdfShareURL) {
                    Label("Share as PDF", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoSecondary)
                .simultaneousGesture(TapGesture().onEnded { onShared?() })
            } else {
                Button {
                    preparePDF(document)
                } label: {
                    Label("Prepare PDF", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoSecondary)
            }
        }
        .padding(.top, TempoSpacing.sm)
    }

    private func preparePDF(_ document: TrainerReportDocument) {
        let data = TrainerReportPDFRenderer.renderPDF(for: document)
        let filename = "trainer-report-\(document.scope.rawValue)-\(language.rawValue).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            pdfShareURL = url
        } catch {
            pdfErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Data assembly

    private func rebuild() {
        pdfShareURL = nil
        // A previous enrichment fetch (for the old scope/language) must never
        // land on the document we're about to build fresh.
        footballEnrichmentTask?.cancel()
        document = Self.buildDocument(program: program, scope: scope, language: language, modelContext: modelContext)
        footballEnrichmentTask = Task { @MainActor in
            await enrichFootballWithWhoopIfNeeded()
        }
    }

    /// Whoop-football feature — best-effort network fallback for football
    /// match days with no persisted `ActivitySession` (§ "Only if nothing is
    /// persisted, fetch Whoop workouts ... async, with the report still
    /// rendering immediately"). `buildDocument` above already rendered the
    /// document synchronously from persisted data alone; this only ever
    /// ADDS numbers to it later, never blocks the initial render, and is a
    /// no-op (leaves the document exactly as-is) when Whoop is disconnected,
    /// in demo mode, slow, or errors out.
    @MainActor
    private func enrichFootballWithWhoopIfNeeded() async {
        guard services.whoop.providesRealData else {
            return
        }
        let scopeRange = TrainerReportBuilder.scheduleRange(for: scope, program: program)
        let searchRange = TrainerReportBuilder.searchRange(around: scopeRange)
        let matchesInScope = Self.fetchMatches(in: searchRange, modelContext: modelContext)
            .filter { scopeRange.contains(Calendar.current.startOfDay(for: $0.kickoff)) }
        guard !matchesInScope.isEmpty else {
            return
        }

        let persisted = Self.fetchFootballActivitySessions(in: searchRange, modelContext: modelContext)
        let cal = Calendar.current
        let needsLookup = matchesInScope.filter {
            TrainerReportSupplementalSections.footballStats(matching: $0.kickoff, in: persisted, calendar: cal) == nil
        }
        guard !needsLookup.isEmpty else {
            return
        }

        var fetched: [ActivitySession] = []
        for match in needsLookup {
            if Task.isCancelled {
                return
            }
            guard let workout = await Self.fetchSoccerWorkout(on: match.kickoff, whoop: services.whoop) else {
                continue
            }
            fetched.append(ActivitySession(
                date: match.kickoff,
                startTime: workout.startTime,
                workoutType: WorkoutType.football.rawValue,
                sportID: workout.sportID,
                source: "whoop",
                strain: workout.strain,
                averageHeartRate: workout.averageHeartRate,
                maxHeartRate: workout.maxHeartRate,
                caloriesBurned: workout.caloriesBurned,
                durationMinutes: workout.durationMinutes
            ))
        }
        guard !fetched.isEmpty, !Task.isCancelled else {
            return
        }
        // Rebuilds from scratch (cheap — local fetches + pure computation)
        // rather than patching `document` in place, so the missed-row
        // relabeling / summary recompute in
        // `TrainerReportSupplementalSections.apply` never runs twice over
        // its own output.
        document = Self.buildDocument(
            program: program, scope: scope, language: language, modelContext: modelContext,
            extraFootballActivities: fetched
        )
    }

    /// Races a single-day Whoop workouts fetch against a short timeout so a
    /// slow or hanging network call can never block the report. Returns the
    /// longest soccer-tagged workout on `date`, or nil on timeout, error, or
    /// no soccer activity that day.
    private static func fetchSoccerWorkout(
        on date: Date,
        whoop: any WhoopServiceProtocol,
        timeout: Duration = .seconds(4)
    ) async -> WhoopWorkoutData? {
        await withTaskGroup(of: WhoopWorkoutData?.self) { group in
            group.addTask {
                let workouts = await (try? whoop.fetchWorkouts(for: date)) ?? []
                return workouts.filter { $0.sportID == 1 }.max { $0.durationMinutes < $1.durationMinutes }
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            // `next()` is `WhoopWorkoutData??` — outer optional is "no more
            // child tasks" (never true here, both always return), inner is
            // the winning task's own result. Flatten rather than `?? nil`
            // (redundant-nil-coalescing false positive on the flattening idiom).
            let result = await (group.next()).flatMap(\.self)
            group.cancelAll()
            return result
        }
    }

    /// Fetches everything `TrainerReportBuilder.build` needs for `program`
    /// and runs it — the whole ModelContext-touching assembly, factored out
    /// of `rebuild()` so the Sunday wrap-up feature (`SundayWrapUpSheet`,
    /// which needs the exact same document for its recap step) can call it
    /// without re-fetching or duplicating any of this.
    ///
    /// `extraFootballActivities` — Whoop-football feature — additional
    /// (not-yet-persisted) football `ActivitySession` facts to merge in on
    /// top of whatever's already saved, used by the async network-fallback
    /// enrichment above. Empty by default: every existing call site
    /// (including `SundayWrapUpSheet`) is unaffected and stays
    /// persisted-data-only.
    @MainActor
    static func buildDocument(
        program: TrainerProgram,
        scope: TrainerReportScope,
        language: TrainerReportLanguage,
        modelContext: ModelContext,
        extraFootballActivities: [ActivitySession] = []
    ) -> TrainerReportDocument {
        let scopeRange = TrainerReportBuilder.scheduleRange(for: scope, program: program)
        let searchRange = TrainerReportBuilder.searchRange(around: scopeRange)

        let plans = fetchPlans(in: searchRange, modelContext: modelContext)
        let planIDs = Set(plans.map(\.id))
        let personalRecords = fetchPersonalRecords(matching: planIDs, modelContext: modelContext)
        let recoveryScores = fetchRecoveryScores(in: searchRange, modelContext: modelContext)
        let painFlaggedExerciseIDs = fetchPainFlaggedExerciseIDs(in: searchRange, modelContext: modelContext)

        let input = TrainerReportInput(
            program: program,
            scope: scope,
            scopeRange: scopeRange,
            plans: plans,
            personalRecords: personalRecords,
            recoveryScores: recoveryScores,
            painFlaggedExerciseIDs: painFlaggedExerciseIDs,
            conditioningProvider: StoredConditioningResults(
                results: fetchConditioningResults(forPlans: planIDs, modelContext: modelContext),
                program: program
            ),
            // Week-over-week progress feature.
            weekOverWeek: WeekOverWeekProgressLoader.load(scopeRange: scopeRange, modelContext: modelContext)
        )
        let built = TrainerReportBuilder.build(input: input, language: language)

        // Pause/travel-pain feature — football/pain/pauses/travel-swap
        // sections, and the pause/match-day-aware relabeling of missed rows
        // (TrainerReportSupplementalSections.swift). Applied here so the
        // Sunday wrap-up recap sees the same document as the report sheet.
        let supplementalInput = TrainerReportSupplementalSections.Input(
            pauses: fetchTrainingPauses(modelContext: modelContext),
            matches: fetchMatches(in: searchRange, modelContext: modelContext),
            plans: plans,
            painReports: fetchPainReports(in: searchRange, modelContext: modelContext),
            // Whoop-football feature — persisted first, network fallback
            // (`extraFootballActivities`) merged on top when the async
            // enrichment above found something persisted data didn't have.
            footballActivities: fetchFootballActivitySessions(in: searchRange, modelContext: modelContext) + extraFootballActivities,
            scopeRange: scopeRange
        )
        return TrainerReportSupplementalSections.apply(to: built, input: supplementalInput, language: language)
    }

    private static func fetchTrainingPauses(modelContext: ModelContext) -> [TrainingPause] {
        (try? modelContext.fetch(FetchDescriptor<TrainingPause>())) ?? []
    }

    private static func fetchMatches(in range: ClosedRange<Date>, modelContext: ModelContext) -> [Match] {
        let lower = range.lowerBound
        let upper = Calendar.current.date(byAdding: .day, value: 1, to: range.upperBound) ?? range.upperBound
        let descriptor = FetchDescriptor<Match>(predicate: #Predicate<Match> { $0.kickoff >= lower && $0.kickoff < upper })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchPainReports(in range: ClosedRange<Date>, modelContext: ModelContext) -> [PainReport] {
        let lower = range.lowerBound
        let upper = Calendar.current.date(byAdding: .day, value: 1, to: range.upperBound) ?? range.upperBound
        let descriptor = FetchDescriptor<PainReport>(predicate: #Predicate<PainReport> { $0.date >= lower && $0.date < upper })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Whoop-football feature — already-persisted football activity: saved
    /// either by `persistNonGymCompletion` when the athlete confirmed "that
    /// was football" (workoutType == "football") or tagged by Whoop as
    /// soccer (sportID == 1) even if logged under a different plan type.
    /// Preferred over any live Whoop call — see `Input.footballActivities`.
    private static func fetchFootballActivitySessions(
        in range: ClosedRange<Date>,
        modelContext: ModelContext
    ) -> [ActivitySession] {
        let lower = range.lowerBound
        let upper = Calendar.current.date(byAdding: .day, value: 1, to: range.upperBound) ?? range.upperBound
        let footballType = WorkoutType.football.rawValue
        let soccerSportID = 1
        let descriptor = FetchDescriptor<ActivitySession>(
            predicate: #Predicate<ActivitySession> {
                $0.date >= lower && $0.date < upper && ($0.workoutType == footballType || $0.sportID == soccerSportID)
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    static func fetchPlans(in range: ClosedRange<Date>, modelContext: ModelContext) -> [WorkoutPlan] {
        let lower = range.lowerBound
        let upper = Calendar.current.date(byAdding: .day, value: 1, to: range.upperBound) ?? range.upperBound
        let descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate<WorkoutPlan> { $0.date >= lower && $0.date < upper }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchConditioningResults(forPlans planIDs: Set<UUID>, modelContext: ModelContext) -> [ConditioningBlockResult] {
        guard !planIDs.isEmpty else {
            return []
        }
        let all = (try? modelContext.fetch(FetchDescriptor<ConditioningBlockResult>())) ?? []
        return all.filter { $0.workoutPlanID.map(planIDs.contains) ?? false }
    }

    private static func fetchPersonalRecords(matching planIDs: Set<UUID>, modelContext: ModelContext) -> [PersonalRecord] {
        guard !planIDs.isEmpty else {
            return []
        }
        let all = (try? modelContext.fetch(FetchDescriptor<PersonalRecord>())) ?? []
        return all.filter { pr in
            guard let planID = pr.workoutPlanID else {
                return false
            }
            return planIDs.contains(planID)
        }
    }

    private static func fetchRecoveryScores(in range: ClosedRange<Date>, modelContext: ModelContext) -> [Date: Double] {
        let lower = range.lowerBound
        let upper = Calendar.current.date(byAdding: .day, value: 1, to: range.upperBound) ?? range.upperBound
        let descriptor = FetchDescriptor<DailyRecovery>(
            predicate: #Predicate<DailyRecovery> { $0.date >= lower && $0.date < upper }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        var result: [Date: Double] = [:]
        for row in rows {
            result[Calendar.current.startOfDay(for: row.date)] = row.recoveryScore
        }
        return result
    }

    /// Best-effort pain scan — Fix #8 asks for pain/discomfort notes "only
    /// if cheaply available". Reimplemented locally over `SetFeedback.note`
    /// free text rather than depending on `TrainingViewModel.noteSignals`
    /// (an instance method on a heavy service object under active edit
    /// elsewhere in this build).
    private static func fetchPainFlaggedExerciseIDs(in range: ClosedRange<Date>, modelContext: ModelContext) -> Set<UUID> {
        let lower = range.lowerBound
        let upper = Calendar.current.date(byAdding: .day, value: 1, to: range.upperBound) ?? range.upperBound
        let descriptor = FetchDescriptor<SetFeedback>(
            predicate: #Predicate<SetFeedback> { $0.capturedAt >= lower && $0.capturedAt < upper && $0.note != nil }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        let keywords = [
            "pain", "hurt", "tweak", "strain", "pinch", "sore", "injury", "tendon", "ache", "sharp",
            "dolore", "male", "fastidio", "infortun", "tira", "pizzic", "gonfio", "contrattura", "strappo",
        ]
        var flagged: Set<UUID> = []
        for row in rows {
            guard let note = row.note?.lowercased(), let exerciseID = row.exerciseID else {
                continue
            }
            if keywords.contains(where: { note.contains($0) }) {
                flagged.insert(exerciseID)
            }
        }
        return flagged
    }
}

// MARK: - Program resolution (for the WorkoutSummaryView entry point)

extension TrainerReportSheet {
    /// Resolves the `TrainerProgram` a `WorkoutPlan.programSessionKey` came
    /// from — the same `<programUUID>#weekIndex#dDayIndex` parsing
    /// `TrainingViewModel.trainerDay(forKey:)` uses, reimplemented here so
    /// this view doesn't need a `TrainingViewModel` in scope.
    static func program(forSessionKey key: String?, modelContext: ModelContext) -> TrainerProgram? {
        guard let key, let programID = key.split(separator: "#").first.flatMap({ UUID(uuidString: String($0)) }) else {
            return nil
        }
        let descriptor = FetchDescriptor<TrainerProgram>(predicate: #Predicate { $0.id == programID })
        return try? modelContext.fetch(descriptor).first
    }
}
