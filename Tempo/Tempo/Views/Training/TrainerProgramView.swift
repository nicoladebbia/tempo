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
    /// Fix #8 — "send report to trainer" (TrainerReportSheet.swift, new file).
    @State
    private var reportProgram: TrainerProgram?

    private var activeProgram: TrainerProgram? {
        programs.first { $0.isActive }
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TempoSpacing.xxl) {
                if let activeProgram {
                    activeCard(activeProgram)
                } else {
                    EmptyStateView(
                        icon: "figure.strengthtraining.traditional",
                        title: "No Trainer Program",
                        message: "Import your coach's program from a photo, PDF, or pasted text. Tempo follows it, adjusted for recovery and match days.",
                        actionTitle: "Import from Trainer",
                        action: { showImport = true }
                    )
                    .padding(.top, TempoSpacing.xxxl)
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
                        HStack {
                            Label("Completion Stats", systemImage: "chart.bar.fill")
                                .font(.tempoBodyBold)
                                .foregroundStyle(Color.tempoTextPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                        .padding(TempoSpacing.cardPaddingCompact)
                        .background(Color.tempoSurfaceCard)
                        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl))
                    }
                }
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.lg)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
        .background(Color.tempoBgPrimary)
        .navigationTitle("Trainer Program")
        .navigationBarTitleDisplayMode(.inline)
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
        }
        .sheet(isPresented: $showImport) {
            TrainerProgramImportView()
        }
        .sheet(item: $reportProgram) { program in
            TrainerReportSheet(program: program)
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
    }

    // MARK: - Active program card

    private func activeCard(_ program: TrainerProgram) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.cardGap) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    Text(program.name)
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(summary(for: program))
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                Spacer()
                Text("ACTIVE")
                    .font(.tempoCaption2.weight(.bold))
                    .foregroundStyle(Color.tempoSignal)
                    .padding(.horizontal, TempoSpacing.sm)
                    .padding(.vertical, TempoSpacing.xxs)
                    .background(Color.tempoSignal.opacity(TempoOpacity.o15))
                    .clipShape(Capsule())
            }

            Text(TrainerProgramDurationText.summary(for: program))
                .font(.tempoCaption1)
                .foregroundStyle(program.isFinished(on: Date()) ? Color.tempoWarning : Color.tempoTextTertiary)

            Divider().background(Color.tempoDivider)

            weekList(program)

            Divider().background(Color.tempoDivider)

            if program.weeks.count > 1 {
                Toggle(isOn: Binding(
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
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Repeats").font(.tempoBodyBold).foregroundStyle(Color.tempoTextPrimary)
                        Text("Loop back to Week 1 after the last week.")
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                }
                .tint(Color.tempoSignal)
            }

            // §13 — off = trainer days get exactly the sets the trainer
            // wrote, no Tempo-added ramp.
            Toggle(isOn: Binding(
                get: { program.warmupsEnabled },
                set: { newValue in
                    program.autoWarmups = newValue
                    _ = modelContext.saveOrAlert("trainer program warm-ups")
                    NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tempo Warm-Up Sets").font(.tempoBodyBold).foregroundStyle(Color.tempoTextPrimary)
                    Text("A 50%/75% ramp before each lift. Off — exactly what your trainer wrote.")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
            .tint(Color.tempoSignal)

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
            .font(.tempoBody)
            .tint(Color.tempoSignal)

            // Fix #6 — editable here too (chosen first on the review screen).
            HStack {
                Text("Schedule")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Picker("Schedule", selection: Binding(
                    get: { program.scheduleMode },
                    set: { newValue in
                        program.scheduleMode = newValue
                        _ = modelContext.saveOrAlert("trainer program schedule mode")
                        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
                    }
                )) {
                    ForEach(TrainerProgramScheduleMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.tempoSignal)
            }
            Text(program.scheduleMode.explanation)
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)

            // Weekly-upload feature — editable here too (chosen first on the
            // review screen).
            HStack {
                Text("New program")
                    .font(.tempoBody)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                Picker("Upload cadence", selection: Binding(
                    get: { program.cadence },
                    set: { newValue in
                        program.cadence = newValue
                        _ = modelContext.saveOrAlert("trainer program cadence")
                        NotificationCenter.default.post(name: .tempoTrainingSettingsChanged, object: nil)
                    }
                )) {
                    ForEach(TrainerProgramCadence.allCases, id: \.self) { option in
                        Text(option.shortName).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .tint(Color.tempoSignal)
            }

            // Fix #8 — report the athlete's logged sessions back to the trainer.
            Button {
                reportProgram = program
            } label: {
                Label("Send Report to Trainer", systemImage: "paperplane")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.tempoSecondary)
            .padding(.top, TempoSpacing.xs)

            HStack(spacing: TempoSpacing.sm) {
                Button {
                    showEdit = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoSecondary)

                Button {
                    TrainerProgramSaver.deactivate(program, modelContext: modelContext)
                } label: {
                    Label("Pause", systemImage: "pause.circle")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoSecondary)
                .accessibilityHint("Stops using this program. You can run it again later.")
            }
            .padding(.top, TempoSpacing.xs)

            Button(role: .destructive) {
                pendingDelete = program
            } label: {
                Label("Delete program", systemImage: "trash")
                    .font(.tempoFootnote)
                    .foregroundStyle(Color.tempoError)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.top, TempoSpacing.xxs)
        }
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl))
    }

    private func weekList(_ program: TrainerProgram) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            ForEach(Array(program.weeks.enumerated()), id: \.offset) { index, week in
                HStack {
                    Text("Week \(index + 1)")
                        .font(.tempoCaption1.weight(.semibold))
                        .foregroundStyle(program.weekIndex(on: Date()) == index ? Color.tempoSignal : Color.tempoTextSecondary)
                    Text(dayNames(week))
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                    Spacer()
                    Text("\(week.days.reduce(0) { $0 + $1.exercises.count }) exercises")
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }
        }
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

    static func shortWeekdayName(_ weekday: Int) -> String {
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        guard (1 ... 7).contains(weekday) else {
            return "?"
        }
        return names[weekday - 1]
    }

    // MARK: - Queued programs (fix #11(b))

    private var queuedSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("UP NEXT")
                .font(.tempoCaption2.weight(.bold))
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(.top, TempoSpacing.sectionHeaderTop)

            ForEach(queuedPrograms) { program in
                HStack(spacing: TempoSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(program.name)
                            .font(.tempoHeadline)
                            .foregroundStyle(Color.tempoTextPrimary)
                        if let date = program.queuedActivationDate {
                            Text("Starts \(date.formatted(date: .abbreviated, time: .omitted)) — auto-activates that day")
                                .font(.tempoCaption2)
                                .foregroundStyle(Color.tempoTextTertiary)
                        }
                    }
                    Spacer()
                    Button {
                        pendingDelete = program
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.tempoError)
                    }
                    .accessibilityLabel("Delete \(program.name)")
                }
                .padding(TempoSpacing.cardPaddingCompact)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl))
            }
        }
    }

    // MARK: - Past programs

    private var pastSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.md) {
            Text("PAST PROGRAMS")
                .font(.tempoCaption2.weight(.bold))
                .foregroundStyle(Color.tempoTextTertiary)
                .padding(.top, TempoSpacing.sectionHeaderTop)

            ForEach(pastPrograms) { program in
                HStack(spacing: TempoSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(program.name)
                            .font(.tempoHeadline)
                            .foregroundStyle(Color.tempoTextPrimary)
                        Text(summary(for: program))
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                    Spacer()
                    Button("Run") {
                        pendingActivate = program
                    }
                    .buttonStyle(.tempoGhost)
                    Button {
                        pendingDelete = program
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.tempoError)
                    }
                    .accessibilityLabel("Delete \(program.name)")
                }
                .padding(TempoSpacing.cardPaddingCompact)
                .background(Color.tempoSurfaceCard)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl))
            }
        }
    }
}
