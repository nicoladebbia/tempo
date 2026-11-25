//
// TrainerProgramView.swift
// Tempo
//
// "Trainer Program": the one page for the athlete's own coach. The active
// program (completion so far, weeks, repeats and start-date controls, edit,
// pause, delete), the report to send back to the trainer, the changes the
// trainer sent (`TrainerChangesSection`), the programs queued next and the
// past programs with how much of each was done. The program is imported from
// a photo, PDF or pasted text; the import stays one tap away (the + button,
// or the bottom button before there is a program). Reached from the Train
// tab's ☰ menu.
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
    /// The Undo toast after a program is deleted.
    @State
    private var toast: ToastData?
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
    /// The same numbers for each past program, by program id.
    @State
    private var pastStats: [UUID: TrainerProgramHistoryStats.Stats] = [:]

    private var activeProgram: TrainerProgram? {
        programs.first { $0.isActive }
    }

    /// Deletes the program and offers Undo for a few seconds. The program is
    /// copied first; Undo puts it back as it was and the week is rebuilt from it
    /// again, the way it was when the program was first switched on.
    private func delete(_ program: TrainerProgram) {
        let snapshot = TrainerProgramSnapshot(program)
        modelContext.delete(program)
        _ = modelContext.saveOrAlert("trainer program delete")
        if snapshot.isActive {
            NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
        }
        toast = ToastData(message: String(localized: "Deleted \(snapshot.name)"), style: .info, actionTitle: String(localized: "Undo")) {
            snapshot.restore(in: modelContext)
            _ = modelContext.saveOrAlert("trainer program restore")
            if snapshot.isActive {
                NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
            }
        }
    }

    /// What the compliance numbers depend on among the program's own fields.
    private var complianceKey: String {
        let past = pastPrograms.map { "\($0.id)-\($0.startDate.timeIntervalSince1970)-\($0.endedAt?.timeIntervalSince1970 ?? 0)" }
        let active = activeProgram.map {
            "\($0.id)-\($0.startDate.timeIntervalSince1970)-\($0.weeks.count)-\($0.skippedSessions.count)-\($0.scheduleMode.rawValue)"
        } ?? "none"
        return "\(active)|\(past.joined(separator: ","))"
    }

    /// One fetch of the plans and overrides feeds every program's numbers.
    private func refreshCompliance() {
        let plans = (try? modelContext.fetch(FetchDescriptor<WorkoutPlan>())) ?? []
        let overrides = TrainerScheduleOverrides.fetch(modelContext: modelContext)
        complianceStats = activeProgram.map {
            TrainerProgramHistoryStats.stats(for: $0, plans: plans, overrides: overrides)
        }
        var past: [UUID: TrainerProgramHistoryStats.Stats] = [:]
        for program in pastPrograms {
            past[program.id] = TrainerProgramHistoryStats.stats(for: program, plans: plans, overrides: overrides)
        }
        pastStats = past
    }

    /// Fix #11(b) — queued to auto-activate later; not "past" (history) and
    /// not the running program.
    private var queuedPrograms: [TrainerProgram] {
        programs.filter { !$0.isActive && $0.queuedActivationDate != nil }
    }

    /// Fix #11(c) — archived (finished/replaced) programs, listed under "Past
    /// programs" with their completion; a queued one isn't history yet.
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
            }
        }
        .tidePage()
        .navigationTitle("Trainer Program")
        .firstTip(
            "train.program",
            "Import your trainer's program from a photo, PDF or pasted text and Tempo shows each day's session in Training.",
            systemImage: "square.and.arrow.down"
        )
        .navigationBarTitleDisplayMode(.inline)
        .tempoToast($toast)
        .task(id: complianceKey) {
            refreshCompliance()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoWorkoutChanged)) { _ in
            refreshCompliance()
        }
        // The one thing to do here sits under the thumb: send the report back
        // to the trainer, or bring the program in when there is none yet.
        .safeAreaBar(edge: .bottom) {
            mainActionBar
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
                delete(program)
            }
        } message: { _ in
            Text("Your workout history stays either way.")
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
        VStack(spacing: Tide.s5) {
            programHero(program)
            TrainerChangesSection(program: program) {
                feedbackProgram = program
            }
            VStack(alignment: .leading, spacing: Tide.s3) {
                TideSectionLabel(title: String(localized: "Program settings"))
                settingsCard(program)
            }
            actionsBlock(program)
        }
    }

    /// The hero: how much of the program is done, with the program's name,
    /// its weeks and where it stands in time under it.
    private func programHero(_ program: TrainerProgram) -> some View {
        let scheduled = complianceStats?.scheduled ?? 0
        let percent = Int(((complianceStats?.fraction ?? 0) * 100).rounded())
        var chips = [String(localized: "Active")]
        if let current = program.weekIndex(on: Date()), program.weeks.count > 1 {
            chips.append(String(localized: "Week \(current + 1) of \(program.weeks.count)"))
        }
        return TrainDayHero(
            label: String(localized: "Sessions done"),
            figure: complianceStats.map { "\($0.done)" } ?? "–",
            unit: scheduled > 0 ? String(localized: "of \(scheduled)") : nil,
            caption: scheduled > 0 ? program.name : String(localized: "\(program.name) · No sessions due yet."),
            chips: chips,
            figureExplainer: TrainExplainers.sessionsDone
        ) {
            if scheduled > 0 {
                TrainRing(progress: complianceStats?.fraction ?? 0, diameter: TideTrain.heroRing) {
                    TideNumber("\(percent)", unit: "%", size: Tide.numeralS, relativeTo: .title2)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Completion")
                .accessibilityValue("\(percent) percent")
            }
        } footer: {
            VStack(alignment: .leading, spacing: Tide.s3) {
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text(summary(for: program))
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                    // A repeating block's duration line only repeats the summary above.
                    if program.cadence != .block || !program.repeats {
                        Text(TrainerProgramDurationText.summary(for: program))
                            .font(Tide.caption)
                            .foregroundStyle(program.isFinished(on: Date()) ? TideTrain.caution : Tide.text3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                weekList(program)
            }
        }
    }

    private func settingsCard(_ program: TrainerProgram) -> some View {
        TrainPlanCard {
            if program.weeks.count > 1 {
                TrainPlanToggleRow(
                    title: String(localized: "Repeats"),
                    detail: String(localized: "Loop back to Week 1 after the last week."),
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
                title: String(localized: "Tempo Warm-Up Sets"),
                detail: String(localized: "A 50%/75% ramp before each lift. Off — exactly what your trainer wrote."),
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
                title: String(localized: "Schedule"),
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
                title: String(localized: "New program"),
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

    /// The page's main action, in the thumb zone. With a program: report the
    /// logged sessions back to the trainer (the weekly job). Without one:
    /// bring the trainer's program in.
    @ViewBuilder
    private var mainActionBar: some View {
        if let activeProgram {
            Button {
                reportProgram = activeProgram
            } label: {
                Label("Send Report to Trainer", systemImage: "paperplane")
            }
            .buttonStyle(.tidePrimary)
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s2)
        } else {
            Button {
                showImport = true
            } label: {
                Label("Import from Trainer", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.tidePrimary)
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s2)
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
        .buttonStyle(.trainPlanSecondary)
    }

    private func pauseButton(_ program: TrainerProgram) -> some View {
        Button {
            pendingPause = program
        } label: {
            Label("Pause", systemImage: "pause.circle")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.trainPlanSecondary)
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
                        Text(TrainCount.text(count, "exercise"))
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        weekLabel(index, isCurrent: isCurrent)
                        Text(dayNames(week))
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                        Text(TrainCount.text(count, "exercise"))
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
        let weekLabel = weekCount == 1 ? String(localized: "1 week") : String(localized: "\(weekCount) weeks")
        let dayLabel = dayCount == 1 ? String(localized: "1 day/week") : String(localized: "\(dayCount) days/week")
        let cadence = program.repeats ? String(localized: "repeats") : String(localized: "runs once")
        return "\(weekLabel) · \(dayLabel) · \(cadence)"
    }

    /// trainer-feedback-tests — `nonisolated` so `TrainerFeedbackApplier`
    /// (a plain, non-MainActor enum, unit-tested with no actor context at
    /// all) can call this pure formatter without an `await`. Purely
    /// computational — no view state involved.
    nonisolated static func shortWeekdayName(_ weekday: Int) -> String {
        guard (1 ... 7).contains(weekday) else {
            return "?"
        }
        // 1 = Monday ... 7 = Sunday; Calendar's symbols start on Sunday.
        return Calendar.current.shortWeekdaySymbols[weekday % 7]
    }

    // MARK: - Queued programs (fix #11(b))

    private var emptyState: some View {
        TrainEmptyCard(
            systemImage: "figure.strengthtraining.traditional",
            title: String(localized: "No trainer program yet"),
            message: String(localized: "Import your coach's program from a photo, PDF, or pasted text. Tempo follows it, adjusted for recovery and match days.")
        )
        .padding(.top, Tide.s4)
    }

    private var queuedSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            TideSectionLabel(title: String(localized: "Up next"))
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
                    TrainIconButton(systemImage: "trash", label: String(localized: "Delete \(program.name)"), tint: Tide.danger) {
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
            TideSectionLabel(title: String(localized: "Past programs"))
                .padding(.top, Tide.s2)

            ForEach(pastPrograms) { program in
                pastRow(program)
            }
        }
    }

    /// A past program: what it was, how much of it was done, and Run / delete.
    private func pastRow(_ program: TrainerProgram) -> some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
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
            if let stats = pastStats[program.id] {
                TrainPlanDivider()
                TrainerComplianceBar(stats: stats, emptyText: String(localized: "No sessions were ever generated for this program."))
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
            Text("\(TrainerProgramDurationText.historyText(for: program)) · \(program.scheduleMode.displayName)")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pastActions(_ program: TrainerProgram) -> some View {
        HStack(spacing: Tide.s2) {
            Button {
                pendingActivate = program
            } label: {
                Text(String(localized: "trainer.past.run", defaultValue: "Run", comment: "Button on a past trainer program: start this program again (not the sport)"))
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, Tide.s5)
                    .frame(minHeight: Tide.hit)
                    .glassEffect(.regular.tint(Tide.glassControl).interactive(), in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            TrainIconButton(systemImage: "trash", label: String(localized: "Delete \(program.name)"), tint: Tide.danger) {
                pendingDelete = program
            }
        }
    }
}
