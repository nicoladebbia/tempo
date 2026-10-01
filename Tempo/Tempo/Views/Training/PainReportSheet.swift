//
// PainReportSheet.swift
// Tempo
//
// "This hurts" flow (pause/travel-pain feature) — reached from a long-press
// on any exercise row (`TodayWorkoutView`'s context menu) and from the active
// workout's exercise header (`ActiveWorkoutView`). Careful, non-medical tone
// throughout — no diagnosis, ever; see `TrainingViewModel+Pain.swift` for the
// tier logic this UI drives.
//

import SwiftData
import SwiftUI

// MARK: - PainReportSheet

struct PainReportSheet: View {
    @Bindable
    var viewModel: TrainingViewModel
    let plannedExercise: PlannedExercise?

    @Environment(\.modelContext)
    private var modelContext
    @Environment(\.dismiss)
    private var dismiss

    @State
    private var bodyArea: PainBodyArea = .knee
    @State
    private var severity: Double = 4
    @State
    private var note = ""
    @State
    private var filedReport: PainReport?
    @State
    private var swapChoices: [Exercise] = []
    /// Set when `applyPainSwap` refuses (a set on this exercise is already
    /// logged) — see that function's doc comment.
    @State
    private var swapFailedMessage: String?

    private var tier: PainSeverityTier {
        PainSeverityTier(severity: Int(severity))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let filedReport {
                    outcome(for: filedReport)
                } else {
                    form
                }
            }
            .navigationTitle("This hurts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Step 1: report

    private var form: some View {
        Form {
            Section("Where") {
                Picker("Body area", selection: $bodyArea) {
                    ForEach(PainBodyArea.allCases, id: \.self) { area in
                        Label(area.displayName, systemImage: area.symbolName).tag(area)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section("How bad, 1–10") {
                VStack(alignment: .leading, spacing: TempoSpacing.xs) {
                    HStack {
                        Text("\(Int(severity))")
                            .font(.tempoDataMedium)
                            .foregroundStyle(severityColor)
                        Spacer()
                        Text(tierLabel)
                            .font(.tempoCaption1.weight(.semibold))
                            .foregroundStyle(severityColor)
                    }
                    Slider(value: $severity, in: 1 ... 10, step: 1)
                        .tint(severityColor)
                }
            }

            Section("Note (optional)") {
                TextField("e.g. sharp on the way down", text: $note, axis: .vertical)
                    .lineLimit(2 ... 4)
            }

            Section {
                Text(disclaimer)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                submit()
            } label: {
                Text("Report")
                    .font(.tempoSubheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(Color.tempoTextInverse)
                    .background(Color.tempoSignal)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(TempoSpacing.md)
            .background(.bar)
        }
    }

    private var tierLabel: String {
        switch tier {
        case .mild: "Mild"
        case .moderate: "Moderate"
        case .severe: "Severe"
        }
    }

    private var severityColor: Color {
        switch tier {
        case .mild: Color.tempoSuccess
        case .moderate: Color.tempoAmber
        case .severe: Color.tempoError
        }
    }

    private var disclaimer: String {
        "Tempo isn't a medical service and this isn't a diagnosis. For anything that doesn't settle, see a doctor or physio."
    }

    private func submit() {
        let report = viewModel.filePainReport(
            plannedExercise: plannedExercise,
            bodyArea: bodyArea,
            severity: Int(severity),
            note: note.isEmpty ? nil : note,
            modelContext: modelContext
        )
        if tier == .moderate, let plannedExercise {
            swapChoices = viewModel.painFreeSwapAlternatives(for: plannedExercise, modelContext: modelContext)
        }
        filedReport = report
    }

    // MARK: - Step 2: outcome by tier

    @ViewBuilder
    private func outcome(for report: PainReport) -> some View {
        switch tier {
        case .mild:
            mildOutcome
        case .moderate:
            moderateOutcome(report)
        case .severe:
            severeOutcome(report)
        }
    }

    private var mildOutcome: some View {
        outcomeShell(
            icon: "checkmark.circle.fill", color: .tempoSuccess,
            title: "Load reduced 20%",
            message: "This exercise's remaining sets today are lighter. Stop again if it doesn't ease up."
        ) {
            doneButton
        }
    }

    private func moderateOutcome(_ report: PainReport) -> some View {
        outcomeShell(
            icon: "arrow.triangle.2.circlepath", color: .tempoAmber,
            title: "Swap it or skip it",
            message: "Moderate pain — pick a pain-free alternative for the same muscle, or skip this exercise for today."
        ) {
            VStack(spacing: TempoSpacing.sm) {
                if let message = swapFailedMessage {
                    Text(message)
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoError)
                        .multilineTextAlignment(.center)
                }
                if let plannedExercise, !swapChoices.isEmpty {
                    ForEach(Array(swapChoices.prefix(4)), id: \.id) { alt in
                        Button {
                            if viewModel.applyPainSwap(report, plannedExercise: plannedExercise, to: alt, modelContext: modelContext) {
                                dismiss()
                            } else {
                                swapFailedMessage = "You've already logged a set on this one — swapping mid-exercise isn't safe. Skip it instead."
                            }
                        } label: {
                            HStack {
                                Text(alt.name)
                                    .font(.tempoBody)
                                Spacer()
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            .foregroundStyle(Color.tempoTextPrimary)
                            .padding(TempoSpacing.md)
                            .frame(maxWidth: .infinity)
                            .background(Color.tempoSurfaceCard)
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button(role: .destructive) {
                    if let plannedExercise {
                        viewModel.skipExerciseDueToPain(report, plannedExercise: plannedExercise, modelContext: modelContext)
                    }
                    dismiss()
                } label: {
                    Text("Skip this exercise")
                        .font(.tempoSubheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func severeOutcome(_ report: PainReport) -> some View {
        let canEnd = viewModel.canEndSessionForPain
        return outcomeShell(
            icon: "exclamationmark.octagon.fill", color: .tempoError,
            title: "Stop this exercise",
            message: canEnd
                ? "That's a lot of pain to push through. Consider ending the session — and if it doesn't settle down, get it looked at by a professional."
                : "That's a lot of pain to push through. Skip it today — and if it doesn't settle down, get it looked at by a professional."
        ) {
            VStack(spacing: TempoSpacing.sm) {
                if canEnd {
                    Button(role: .destructive) {
                        if let plannedExercise {
                            viewModel.skipExerciseDueToPain(report, plannedExercise: plannedExercise, modelContext: modelContext)
                        }
                        dismiss()
                        // Sets logged → summary; none → session closes. The
                        // workout screen follows sessionState, not this sheet.
                        viewModel.endSessionDueToPain(report, modelContext: modelContext)
                    } label: {
                        Text("End the session")
                            .font(.tempoSubheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .foregroundStyle(Color.tempoTextInverse)
                            .background(Color.tempoError)
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    if let plannedExercise {
                        viewModel.skipExerciseDueToPain(report, plannedExercise: plannedExercise, modelContext: modelContext)
                    }
                    dismiss()
                } label: {
                    Text("Just skip this exercise, keep going")
                        .font(.tempoSubheadline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(.tempoSubheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
        .buttonStyle(.bordered)
    }

    private func outcomeShell(
        icon: String, color: Color, title: String, message: String,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        VStack(spacing: TempoSpacing.lg) {
            Spacer(minLength: TempoSpacing.xl)
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(color)
            Text(title)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
            actions()
            Spacer()
        }
        .padding(TempoSpacing.xl)
    }
}
