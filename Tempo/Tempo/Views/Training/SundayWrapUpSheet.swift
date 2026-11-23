//
// SundayWrapUpSheet.swift
// Tempo
//
// Weekly-upload feature — the guided "Wrap up the week" flow
// `WeeklyUploadPromptCard` opens once a `.weekly` program's Sunday-19:00
// deadline hits. Three steps, one screen at a time:
//   (a) Your week — a recap built from the same `TrainerReportBuilder` data
//       and `WeekOverWeekProgress` deltas as the trainer report itself.
//   (b) Send to trainer — the REAL `TrainerReportSheet` embedded directly
//       (its own scope/language pickers, WhatsApp text + PDF share
//       buttons), with a "Skip" escape hatch.
//   (c) Upload next week — the REAL `TrainerProgramImportView` embedded
//       directly, so it keeps its existing multi-source-import + replace-
//       old-week logic untouched.
// Each step supplies its own NavigationStack/title (both embedded views
// already do); this sheet only adds the step-dots header above them and the
// Skip/Continue footer on step (b).
//
// "Upload only" (skip straight to step (c)'s screen with no recap/report) is
// `WeeklyUploadPromptCard`'s separate secondary action, presenting
// `TrainerProgramImportView` directly — this sheet is only the full guided
// flow.
//

import SwiftData
import SwiftUI

// MARK: - SundayWrapUpSheet

struct SundayWrapUpSheet: View {
    let program: TrainerProgram

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @Query private var userSettings: [UserSettings]

    @State
    private var step: Step = .recap
    @State
    private var document: TrainerReportDocument?
    @State
    private var weekOverWeek: WeekOverWeekProgress.Result = .empty
    @State
    private var reportSentThisWeek: Bool

    enum Step: Int, CaseIterable {
        case recap
        case sendReport
        case uploadNext
    }

    init(program: TrainerProgram) {
        self.program = program
        let weekMonday = TrainerProgramWeeklyUpload.servedWeekMonday(for: program)
        _reportSentThisWeek = State(initialValue: SundayWrapUpReportTracker.wasSent(programID: program.id, weekMonday: weekMonday))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                switch step {
                case .recap:
                    recapStep
                case .sendReport:
                    sendReportStep
                case .uploadNext:
                    uploadStep
                }
            }
        }
        .trainSheetRoot()
        .task { rebuildReportData() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button("Close") { dismiss() }
                .font(Tide.body)
                .foregroundStyle(Tide.text2)
                .frame(minHeight: Tide.hit)

            Spacer()

            TrainSessionDots(count: Step.allCases.count, current: step.rawValue)
                .accessibilityHidden(true)

            Spacer()

            // Symmetry spacer so the dots stay visually centered.
            Text("Close")
                .font(Tide.body)
                .hidden()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Tide.edge)
        .padding(.top, Tide.s3)
        .padding(.bottom, Tide.s2)
    }

    // MARK: - Step (a): Your week

    private var recapStep: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Tide.s4) {
                VStack(alignment: .leading, spacing: Tide.hair) {
                    Text("YOUR WEEK").tideLabel(TideTrain.violet)
                    Text(WeeklyUploadPromptCard.wrapUpWeekLabel())
                        .font(Tide.headline)
                        .foregroundStyle(Tide.text)
                }

                if let document {
                    sessionsSummaryCard(document)
                    if !topLiftLines.isEmpty {
                        bulletCard(title: "TOP LIFTS", lines: topLiftLines)
                    }
                    if !topConditioningLines.isEmpty {
                        bulletCard(title: "CONDITIONING", lines: topConditioningLines)
                    }
                    if !prLines.isEmpty {
                        bulletCard(title: "PRS", lines: prLines)
                    }
                    if document.summary.scheduledCount == 0 {
                        Text("No sessions were scheduled this week.")
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text3)
                    }
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .tideCard(padding: Tide.s6, radius: Tide.tileRadius)
                }
            }
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s5)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            Button {
                step = .sendReport
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity, minHeight: TideTrain.bigButton - Tide.s2)
            }
            .buttonStyle(.tidePrimary)
            .disabled(document == nil)
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s3)
        }
    }

    private var topLiftLines: [String] {
        weekOverWeek.exercises
            .sorted { abs($0.e1RMDelta ?? 0) > abs($1.e1RMDelta ?? 0) }
            .prefix(3)
            .map { $0.recapLine(unit: weightUnit) }
    }

    private var weightUnit: WeightUnit {
        userSettings.first?.weightUnit ?? .kg
    }

    private var topConditioningLines: [String] {
        weekOverWeek.conditioning.prefix(3).map(\.recapLine)
    }

    private var prLines: [String] {
        (document?.sessions.flatMap(\.prs).map(\.text)) ?? []
    }

    private func sessionsSummaryCard(_ document: TrainerReportDocument) -> some View {
        let summary = document.summary
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Tide.s3))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Tide.s3))
        return VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Sessions").tideLabel()
            layout {
                TrainStat(value: "\(summary.doneCount)", label: "done", color: TideTrain.positive)
                TrainStat(value: "\(summary.missedCount)", label: "missed", color: summary.missedCount > 0 ? TideTrain.caution : Tide.text)
                TrainStat(value: "\(summary.movedCount)", label: "moved")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    private func bulletCard(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text(title).tideLabel()
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text("• \(line)")
                    .font(Tide.body)
                    .foregroundStyle(Tide.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    // MARK: - Step (b): Send to trainer

    private var sendReportStep: some View {
        VStack(spacing: 0) {
            if reportSentThisWeek {
                HStack(spacing: Tide.s1) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(TideTrain.positive)
                    Text("Report already sent this week")
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                }
                .padding(.bottom, Tide.s1)
            }

            TrainerReportSheet(program: program, onShared: markReportSent, embedded: true, referenceDate: wrapUpSunday)

            let footer = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Tide.s2))
                : AnyLayout(HStackLayout(spacing: Tide.s3))
            footer {
                Button {
                    step = .uploadNext
                } label: {
                    Text("Skip")
                        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil, minHeight: TideTrain.bigButton - Tide.s2)
                }
                .buttonStyle(.tideGlass)

                Button {
                    markReportSent()
                    step = .uploadNext
                } label: {
                    Text("Sent — Continue")
                        .frame(maxWidth: .infinity, minHeight: TideTrain.bigButton - Tide.s2)
                }
                .buttonStyle(.tidePrimary)
                .layoutPriority(1)
            }
            .padding(.horizontal, Tide.edge)
            .padding(.top, Tide.s2)
            .padding(.bottom, Tide.s3)
        }
    }

    // MARK: - Step (c): Upload next week

    /// The real import flow, embedded as-is — its own "replace the old week"
    /// logic (`TrainerProgramSaver`) is untouched. Its `dismiss()` (on save
    /// or cancel) closes THIS sheet too, since it isn't presented as its own
    /// nested `.sheet` here — which is correct: there's no further wrap-up
    /// step after this one either way.
    private var uploadStep: some View {
        TrainerProgramImportView()
    }

    // MARK: - Data assembly

    /// The Sunday closing the week this wrap-up covers (the week just
    /// finished, even when opened late on Mon+).
    private var wrapUpSunday: Date {
        TrainerProgramWeeklyUpload.wrapUpWeekSunday(now: Date())
    }

    private func rebuildReportData() {
        let scopeRange = TrainerReportBuilder.scheduleRange(for: .week, program: program, today: wrapUpSunday)
        document = TrainerReportSheet.buildDocument(
            program: program,
            scope: .week,
            language: TrainerReportBuilder.detectLanguage(program: program),
            modelContext: modelContext,
            today: wrapUpSunday
        )
        weekOverWeek = WeekOverWeekProgressLoader.load(scopeRange: scopeRange, modelContext: modelContext)
    }

    private func markReportSent() {
        guard !reportSentThisWeek else {
            return
        }
        reportSentThisWeek = true
        let weekMonday = TrainerProgramWeeklyUpload.servedWeekMonday(for: program)
        SundayWrapUpReportTracker.markSent(programID: program.id, weekMonday: weekMonday)
    }
}
