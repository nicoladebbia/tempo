//
// TrainerProgramView.swift
// Tempo
//
// "Trainer Program": the athlete's own coach's program, imported from a
// photo/PDF/pasted text. Shows the active program (weeks/days summary,
// current week, repeats/ends + start-date controls, deactivate/delete),
// past programs (activate one — only one active at a time), and the entry
// point into the import flow. Reached from the Training tab's ☰ menu.
//
// Only ONE edit to an existing Training file backs this screen
// (TrainingTabView's menu link) — everything else here is new.
//

import SwiftData
import SwiftUI

// MARK: - TrainerProgramView

struct TrainerProgramView: View {
    @Environment(\.modelContext)
    private var modelContext
    @Environment(ServiceContainer.self)
    private var services
    @Query(sort: \TrainerProgram.createdAt, order: .reverse)
    private var programs: [TrainerProgram]

    @State
    private var showImport = false
    @State
    private var showEdit = false
    @State
    private var pendingDelete: TrainerProgram?
    @State
    private var pendingActivate: TrainerProgram?
    @State
    private var pendingPause: TrainerProgram?
    /// Fix #8 — "send report to trainer" (TrainerReportSheet.swift, new file).
    @State
    private var reportProgram: TrainerProgram?
    /// Pause/travel-pain feature — see AwayModeSheet.swift.
    @State
    private var showAwayMode = false
    @State
    private var awayModeViewModel: TrainingViewModel?
    /// trainer-feedback-tests — "Trainer sent changes" (TrainerFeedbackInputView.swift, new file).
    @State
    private var feedbackProgram: TrainerProgram?
    /// Compliance for the active program. Walks every plan and every day since
    /// the start, so it is computed once here (see `refreshCompliance`), never
    /// inside `body`, which re-runs on every render.
    @State
    private var complianceStats: TrainerProgramHistoryStats.Stats?

    private var activeProgram: TrainerProgram? {
        programs.first { $0.isActive }
    }

    /// What the compliance numbers depend on among the program's own fields.
    private var complianceKey: String {
        guard let program = activeProgram else {
            return "none"
        }
        return "\(program.id)-\(program.startDate.timeIntervalSince1970)-\(program.weeks.count)-\(program.skippedSessions.count)-\(program.scheduleMode.rawValue)"
    }

    private func refreshCompliance() {
        complianceStats = activeProgram.map { TrainerProgramHistoryStats.stats(for: $0, modelContext: modelContext) }
    }

    /// Fix #11(b) — queued to auto-activate later; not "past" (history) and
    /// not the running program.
    private var queuedPrograms: [TrainerProgram] {
        programs.filter { !$0.isActive && $0.queuedActivationDate != nil }
    }

    /// Fix #11(c) — archived (finished/replaced) programs live in
    /// `TrainerProgramHistoryView`; a queued one isn't history yet.
    private var pastPrograms: [TrainerProgram] {
        programs.filter { !$0.isActive && $0.queuedActivationDate == nil }
    }

    var body: some View {
        TrainPlanPage(spacing: Tide.s5) {
            if let activeProgram {
                activeCard(activeProgram)
            } else {
                emptyState
            }

            if !queuedPrograms.isEmpty {
                queuedSection
            }

            if !pastPrograms.isEmpty {
                pastSection

                // Fix #11(c) — same programs, read-only, with basic
                // completion stats (sessions done / scheduled).
                NavigationLink {
                    TrainerProgramHistoryView()
                } label: {
                    TrainRowLabel(systemImage: "chart.bar.fill", title: "Completion Stats")
                        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
                }
                .buttonStyle(.trainCard)
            }
        }
        .tidePage()
        .navigationTitle("Trainer Program")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: complianceKey) {
            refreshCompliance()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoWorkoutChanged)) { _ in
            refreshCompliance()
        }
        .toolbar {
            if activeProgram != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImport = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Import from trainer")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if awayModeViewModel == nil {
                        awayModeViewModel = TrainingViewModel(
                            trainingEngine: services.trainingEngine, whoop: services.whoop, healthKit: services.healthKit
                        )
                    }
                    showAwayMode = true
                } label: {
                    Image(systemName: "airplane")
                }
                .accessibilityLabel("Away from the gym — pause or limited equipment")
            }
        }
        .sheet(isPresented: $showImport) {
            TrainerProgramImportView()
        }
        .sheet(isPresented: $showAwayMode) {
            if let awayModeViewModel {
                AwayModeSheet(viewModel: awayModeViewModel)
            }
        }
        .sheet(item: $reportProgram) { program in
            TrainerReportSheet(program: program)
        }
        .sheet(item: $feedbackProgram) { program in
            TrainerFeedbackInputView(program: program)
        }
        .sheet(isPresented: $showEdit) {
            if let activeProgram {
                TrainerProgramReviewView(editingProgram: activeProgram, onSaved: { showEdit = false })
            }
        }
        .confirmationDialog(
            "Delete this program?",
            isPresented: Binding(get: { pendingDelete != nil }, set: {
                if !$0 {
                    pendingDelete = nil
                }
            }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { program in
            Button("Delete \"\(program.name)\"", role: .destructive) {
                let wasActive = program.isActive
                modelContext.delete(program)
                _ = modelContext.saveOrAlert("trainer program delete")
                if wasActive {
                    NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
                }
            }
        } message: { _ in
            Text("This can't be undone. Your workout history stays either way.")
        }
        .confirmationDialog(
            "Run this program?",
            isPresented: Binding(get: { pendingActivate != nil }, set: {
                if !$0 {
                    pendingActivate = nil
                }
            }),
            titleVisibility: .visible,
            presenting: pendingActivate
        ) { program in
            Button("Run \"\(program.name)\"") {
                TrainerProgramSaver.activate(program, modelContext: modelContext)
            }
        } message: { _ in
            Text("This replaces your current active program (if any). Tempo regenerates the week from it.")
        }
        .confirmationDialog(
            "Pause this program?",
            isPresented: Binding(get: { pendingPause != nil }, set: {
                if !$0 {
                    pendingPause = nil
                }
            }),
            titleVisibility: .visible,
            presenting: pendingPause
        ) { program in
            Button("Pause \"\(program.name)\"") {
                TrainerProgramSaver.deactivate(program, modelContext: modelContext)
            }
        } message: { _ in
            Text("It moves to Past programs and Tempo stops planning from it. Run it again any time. Your history stays.")
        }
    }

    // MARK: - Active program card

    private func activeCard(_ program: TrainerProgram) -> some View {
        VStack(spacing: Tide.s4) {
            programCard(program)
            settingsCard(program)
            actionsBlock(program)
        }
    }

    private func programCard(_ program: TrainerProgram) -> some View {
        TrainPlanCard {
            HStack(alignment: .top, spacing: Tide.s2) {
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(program.name)
                        .font(Tide.title2)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary(for: program))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Tide.s2)
                TrainTag(text: "ACTIVE", color: Color.accentColor)
            }

            Text(TrainerProgramDurationText.summary(for: program))
                .font(Tide.caption)
                .foregroundStyle(program.isFinished(on: Date()) ? TideTrain.caution : Tide.text3)
                .fixedSize(horizontal: false, vertical: true)

            // Compliance: sessions actually done / scheduled so far.
            if let complianceStats {
                TrainerComplianceBar(stats: complianceStats, emptyText: "No sessions due yet.")
            }

            TrainPlanDivider()

            weekList(program)
        }
    }

    private func settingsCard(_ program: TrainerProgram) -> some View {
        TrainPlanCard {
            if program.weeks.count > 1 {
                TrainPlanToggleRow(
                    title: "Repeats",
                    detail: "Loop back to Week 1 after the last week.",
                    isOn: Binding(
                        get: { program.repeats },
                        set: { newValue in
                            program.repeats = newValue
                            _ = modelContext.saveOrAlert("trainer program repeats")
                            // Fix #11 — Repeats changes which week (and, in
                            // sequence mode, whether the program ever finishes)
                            // applies to every future day, so the plan must
                            // regenerate — this was silently missing before.
                            NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
                        }
                    )
                )
                TrainPlanDivider()
            }

            // §13 — off = trainer days get exactly the sets the trainer
            // wrote, no Tempo-added ramp.
            TrainPlanToggleRow(
                title: "Tempo Warm-Up Sets",
                detail: "A 50%/75% ramp before each lift. Off — exactly what your trainer wrote.",
                isOn: Binding(
                    get: { program.warmupsEnabled },
                    set: { newValue in
                        program.autoWarmups = newValue
                        _ = modelContext.saveOrAlert("trainer program warm-ups")
                        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
                    }
                )
            )

            TrainPlanDivider()

            DatePicker(
                "Start date (Monday)",
                selection: Binding(
                    get: { program.startDate },
                    set: { newValue in
                        program.startDate = TrainingCalendar.mondayOfWeek(containing: newValue)
                        _ = modelContext.saveOrAlert("trainer program start date")
                        // Fix #11 — moving the start date shifts which week
                        // every future day maps to; the plan must regenerate
                        // (previously missing — a known gap).
                        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
                    }
                ),
                displayedComponents: .date
            )
            .font(Tide.bodyStrong)
            .tint(Color.accentColor)
            .frame(minHeight: Tide.hit)

            TrainPlanDivider()

            // Fix #6 — editable here too (chosen first on the review screen).
            TrainPlanPickerRow(
                title: "Schedule",
                detail: program.scheduleMode.explanation,
                selection: Binding(
                    get: { program.scheduleMode },
                    set: { newValue in
                        program.scheduleMode = newValue
                        _ = modelContext.saveOrAlert("trainer program schedule mode")
                        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
                    }
                )
            ) {
                ForEach(TrainerProgramScheduleMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            TrainPlanDivider()

            // Weekly-upload feature — editable here too (chosen first on the
            // review screen).
            TrainPlanPickerRow(
                title: "New program",
                selection: Binding(
                    get: { program.cadence },
                    set: { newValue in
                        program.cadence = newValue
                        _ = modelContext.saveOrAlert("trainer program cadence")
                        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
                    }
                )
            ) {
                ForEach(TrainerProgramCadence.allCases, id: \.self) { option in
                    Text(option.shortName).tag(option)
                }
            }
        }
    }

    private func actionsBlock(_ program: TrainerProgram) -> some View {
        VStack(spacing: Tide.s3) {
            // Fix #8 — report the athlete's logged sessions back to the trainer.
            Button {
                reportProgram = program
            } label: {
                Label("Send Report to Trainer", systemImage: "paperplane")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoSecondary)

            // trainer-feedback-tests — paste/screenshot the trainer's reply,
            // review the resulting diff, apply what's accepted.
            Button {
                feedbackProgram = program
            } label: {
                Label("Trainer Sent Changes", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoSecondary)

            if !program.changeLog.isEmpty {
                NavigationLink {
                    TrainerProgramChangeLogView(program: program)
                } label: {
                    HStack(spacing: Tide.s2) {
                        Text("Changes from Trainer")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Tide.s2)
                        Text("\(program.changeLog.count)")
                            .font(TideTrain.figure(.footnote, weight: .semibold))
                            .foregroundStyle(Tide.text2)
                        Image(systemName: "chevron.right")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: Tide.hit)
                    .contentShape(.rect)
                    .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
                }
                .buttonStyle(.trainCard)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: Tide.s2) {
                    editButton(program)
                    pauseButton(program)
                }
                VStack(spacing: Tide.s2) {
                    editButton(program)
                    pauseButton(program)
                }
            }

            Button(role: .destructive) {
                pendingDelete = program
            } label: {
                Label("Delete program", systemImage: "trash")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.danger)
                    .frame(maxWidth: .infinity, minHeight: Tide.hit)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func editButton(_: TrainerProgram) -> some View {
        Button {
            showEdit = true
        } label: {
            Label("Edit", systemImage: "pencil")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tempoSecondary)
    }

    private func pauseButton(_ program: TrainerProgram) -> some View {
        Button {
            pendingPause = program
        } label: {
            Label("Pause", systemImage: "pause.circle")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.tempoSecondary)
        .accessibilityHint("Stops using this program. You can run it again later.")
    }

    private func weekList(_ program: TrainerProgram) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            ForEach(Array(program.weeks.enumerated()), id: \.offset) { index, week in
                let count = week.days.reduce(0) { $0 + $1.exercises.count }
                let isCurrent = program.weekIndex(on: Date()) == index
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Tide.s2) {
                        weekLabel(index, isCurrent: isCurrent)
                        Text(dayNames(week))
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                        Spacer(minLength: Tide.s2)
                        Text("\(count) exercises")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        weekLabel(index, isCurrent: isCurrent)
                        Text(dayNames(week))
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                        Text("\(count) exercises")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                }
            }
        }
    }

    private func weekLabel(_ index: Int, isCurrent: Bool) -> some View {
        Text("Week \(index + 1)")
            .font(Tide.caption.weight(.semibold))
            .foregroundStyle(isCurrent ? Color.accentColor : Tide.text2)
    }

    private func dayNames(_ week: ProgramWeek) -> String {
        week.days
            .sorted { $0.weekday < $1.weekday }
            .map { Self.shortWeekdayName($0.weekday) }
            .joined(separator: " · ")
    }

    private func summary(for program: TrainerProgram) -> String {
        let weekCount = program.weeks.count
        let dayCount = program.weeks.first?.days.count ?? 0
        let weekLabel = weekCount == 1 ? "1 week" : "\(weekCount) weeks"
        let dayLabel = dayCount == 1 ? "1 day/week" : "\(dayCount) days/week"
        let cadence = program.repeats ? "repeats" : "runs once"
        return "\(weekLabel) · \(dayLabel) · \(cadence)"
    }

    /// trainer-feedback-tests — `nonisolated` so `TrainerFeedbackApplier`
    /// (a plain, non-MainActor enum, unit-tested with no actor context at
    /// all) can call this pure formatter without an `await`. Purely
    /// computational — no view state involved.
    nonisolated static func shortWeekdayName(_ weekday: Int) -> String {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        guard (1 ... 7).contains(weekday) else {
            return "?"
        }
        return names[weekday - 1]
    }

    // MARK: - Queued programs (fix #11(b))

    private var emptyState: some View {
        VStack(spacing: Tide.s4) {
            TrainEmptyCard(
                systemImage: "figure.strengthtraining.traditional",
                title: "No Trainer Program",
                message: "Import your coach's program from a photo, PDF, or pasted text. Tempo follows it, adjusted for recovery and match days."
            )
            Button {
                showImport = true
            } label: {
                Text("Import from Trainer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tidePrimary)
        }
        .padding(.top, Tide.s4)
    }

    private var queuedSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Up next")
                .padding(.top, Tide.s2)

            ForEach(queuedPrograms) { program in
                HStack(spacing: Tide.s3) {
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(program.name)
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let date = program.queuedActivationDate {
                            Text("Starts \(date.formatted(date: .abbreviated, time: .omitted)) — auto-activates that day")
                                .font(Tide.caption)
                                .foregroundStyle(Tide.text2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: Tide.s2)
                    TrainIconButton(systemImage: "trash", label: "Delete \(program.name)", tint: Tide.danger) {
                        pendingDelete = program
                    }
                }
                .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
            }
        }
    }

    // MARK: - Past programs

    private var pastSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: "Past programs")
                .padding(.top, Tide.s2)

            ForEach(pastPrograms) { program in
                pastRow(program)
            }
        }
    }

    private func pastRow(_ program: TrainerProgram) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Tide.s3) {
                pastInfo(program)
                Spacer(minLength: Tide.s2)
                pastActions(program)
            }
            VStack(alignment: .leading, spacing: Tide.s3) {
                pastInfo(program)
                pastActions(program)
            }
        }
        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
    }

    private func pastInfo(_ program: TrainerProgram) -> some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            Text(program.name)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(summary(for: program))
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pastActions(_ program: TrainerProgram) -> some View {
        HStack(spacing: Tide.s2) {
            Button {
                pendingActivate = program
            } label: {
                Text("Run")
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, Tide.s5)
                    .frame(minHeight: Tide.hit)
                    .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            TrainIconButton(systemImage: "trash", label: "Delete \(program.name)", tint: Tide.danger) {
                pendingDelete = program
            }
        }
    }
}
