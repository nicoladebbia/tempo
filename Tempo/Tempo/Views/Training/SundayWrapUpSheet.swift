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
        .background(Color.tempoBgPrimary)
        .task { rebuildReportData() }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button("Close") { dismiss() }
                .font(.tempoSubheadline)
                .foregroundStyle(Color.tempoTextSecondary)

            Spacer()

            HStack(spacing: TempoSpacing.xs) {
                ForEach(Step.allCases, id: \.rawValue) { candidate in
                    Circle()
                        .fill(candidate == step ? Color.tempoViolet : Color.tempoDivider)
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityHidden(true)

            Spacer()

            // Symmetry spacer so the dots stay visually centered.
            Text("Close").font(.tempoSubheadline).opacity(0)
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
        .padding(.top, TempoSpacing.md)
        .padding(.bottom, TempoSpacing.sm)
    }

    // MARK: - Step (a): Your week

    private var recapStep: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: TempoSpacing.lg) {
                VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                    Text("YOUR WEEK")
                        .font(.tempoCaption2.weight(.semibold))
                        .foregroundStyle(Color.tempoViolet)
                    Text(program.name)
                        .font(.tempoTitle3)
                        .foregroundStyle(Color.tempoTextPrimary)
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
                            .font(.tempoCaption1)
                            .foregroundStyle(Color.tempoTextTertiary)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, TempoSpacing.xxl)
                }

                Button {
                    step = .sendReport
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoPrimary)
                .disabled(document == nil)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.bottom, TempoSpacing.bottomSafe + TempoSpacing.xxxxxl)
        }
    }

    private var topLiftLines: [String] {
        weekOverWeek.exercises
            .sorted { abs($0.e1RMDelta ?? 0) > abs($1.e1RMDelta ?? 0) }
            .prefix(3)
            .map(\.recapLine)
    }

    private var topConditioningLines: [String] {
        weekOverWeek.conditioning.prefix(3).map(\.recapLine)
    }

    private var prLines: [String] {
        (document?.sessions.flatMap(\.prs).map(\.text)) ?? []
    }

    private func sessionsSummaryCard(_ document: TrainerReportDocument) -> some View {
        let summary = document.summary
        return VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            Text("SESSIONS")
                .font(.tempoCaption2.weight(.bold))
                .foregroundStyle(Color.tempoTextTertiary)
            Text("\(summary.doneCount) done · \(summary.missedCount) missed · \(summary.movedCount) moved")
                .font(.tempoBodyBold)
                .foregroundStyle(Color.tempoTextPrimary)
        }
        .padding(TempoSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg))
    }

    private func bulletCard(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            Text(title)
                .font(.tempoCaption2.weight(.bold))
                .foregroundStyle(Color.tempoTextTertiary)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text("• \(line)")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }
        }
        .padding(TempoSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg))
    }

    // MARK: - Step (b): Send to trainer

    private var sendReportStep: some View {
        VStack(spacing: 0) {
            if reportSentThisWeek {
                HStack(spacing: TempoSpacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.tempoRecoveryGreen)
                    Text("Report already sent this week")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                }
                .padding(.bottom, TempoSpacing.xs)
            }

            TrainerReportSheet(program: program, onShared: markReportSent, embedded: true)

            HStack(spacing: TempoSpacing.md) {
                Button("Skip") {
                    step = .uploadNext
                }
                .buttonStyle(.tempoSecondary)

                Button {
                    markReportSent()
                    step = .uploadNext
                } label: {
                    Text("Sent — Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.tempoPrimary)
            }
            .padding(.horizontal, TempoSpacing.screenEdge)
            .padding(.top, TempoSpacing.sm)
            .padding(.bottom, TempoSpacing.bottomSafe)
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

    private func rebuildReportData() {
        let scopeRange = TrainerReportBuilder.scheduleRange(for: .week, program: program)
        document = TrainerReportSheet.buildDocument(
            program: program,
            scope: .week,
            language: TrainerReportBuilder.detectLanguage(program: program),
            modelContext: modelContext
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
