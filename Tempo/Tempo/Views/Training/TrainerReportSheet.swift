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

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

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

    init(program: TrainerProgram) {
        self.program = program
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
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

            if let pdfShareURL {
                ShareLink(item: pdfShareURL) {
                    Label("Share as PDF", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoSecondary)
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
        let scopeRange = TrainerReportBuilder.scheduleRange(for: scope, program: program)
        let searchRange = TrainerReportBuilder.searchRange(around: scopeRange)

        let plans = Self.fetchPlans(in: searchRange, modelContext: modelContext)
        let planIDs = Set(plans.map(\.id))
        let personalRecords = Self.fetchPersonalRecords(matching: planIDs, modelContext: modelContext)
        let recoveryScores = Self.fetchRecoveryScores(in: searchRange, modelContext: modelContext)
        let painFlaggedExerciseIDs = Self.fetchPainFlaggedExerciseIDs(in: searchRange, modelContext: modelContext)

        let input = TrainerReportInput(
            program: program,
            scope: scope,
            scopeRange: scopeRange,
            plans: plans,
            personalRecords: personalRecords,
            recoveryScores: recoveryScores,
            painFlaggedExerciseIDs: painFlaggedExerciseIDs,
            conditioningProvider: StoredConditioningResults(
                results: Self.fetchConditioningResults(forPlans: planIDs, modelContext: modelContext),
                program: program
            )
        )
        document = TrainerReportBuilder.build(input: input, language: language)
    }

    private static func fetchPlans(in range: ClosedRange<Date>, modelContext: ModelContext) -> [WorkoutPlan] {
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
