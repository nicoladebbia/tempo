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
    @Environment(\.dynamicTypeSize)
    private var typeSize
    @FocusState
    private var noteFocused: Bool

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
            .trainSheetRoot()
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s5) {
                whereSection
                severityCard
                noteSection

                Text(disclaimer)
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Tide.edge)
            .padding(.vertical, Tide.s3)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            Button {
                submit()
            } label: {
                Text("Report")
            }
            .buttonStyle(.tidePrimary)
            .padding(.horizontal, Tide.edge)
            .padding(.bottom, Tide.s2)
        }
    }

    /// Six body areas as tiles: one tap, no list to open.
    private var whereSection: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("Where").tideLabel()
            LazyVGrid(columns: areaColumns, spacing: Tide.s2) {
                ForEach(PainBodyArea.allCases, id: \.self) { area in
                    Button {
                        bodyArea = area
                        HapticManager.selection()
                    } label: {
                        VStack(spacing: Tide.s1) {
                            Image(systemName: area.symbolName)
                                .font(Tide.headline)
                                .accessibilityHidden(true)
                            Text(area.displayName)
                                .font(Tide.bodyStrong)
                                .lineLimit(1)
                                .minimumScaleFactor(Tide.labelShrink)
                        }
                        .frame(maxWidth: .infinity, minHeight: TideTrain.bigButton)
                    }
                    .buttonStyle(.trainChoice(isSelected: bodyArea == area))
                    .accessibilityLabel(area.displayName)
                }
            }
        }
    }

    private var areaColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Tide.s2),
            count: typeSize.isAccessibilitySize ? 2 : 3
        )
    }

    /// The number is the hero, tinted by how serious it is; the slider moves it.
    private var severityCard: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Text("How bad, 1–10").tideLabel()
            HStack(alignment: .lastTextBaseline) {
                TideNumber(
                    "\(Int(severity))",
                    size: TideTrainSession.stateFigure,
                    relativeTo: .largeTitle,
                    color: severityColor
                )
                Spacer(minLength: Tide.s2)
                Text(tierLabel)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(severityColor)
            }
            .animation(Tide.snap, value: Int(severity))
            Slider(value: $severity, in: 1 ... 10, step: 1)
                .tint(severityColor)
                .accessibilityLabel("Pain from 1 to 10")
                .sensoryFeedback(.selection, trigger: Int(severity))
        }
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text("Note (optional)").tideLabel()
            TextField("e.g. sharp on the way down", text: $note, axis: .vertical)
                .lineLimit(2 ... 4)
                .focused($noteFocused)
                .font(Tide.body)
                .foregroundStyle(Tide.text)
                .tideFieldSurface(focused: noteFocused)
        }
    }

    private var tierLabel: String {
        switch tier {
        case .mild: String(localized: "Mild")
        case .moderate: String(localized: "Moderate")
        case .severe: String(localized: "Severe")
        }
    }

    private var severityColor: Color {
        switch tier {
        case .mild: TideTrain.positive
        case .moderate: TideTrain.caution
        case .severe: Tide.danger
        }
    }

    private var disclaimer: String {
        String(localized: "Tempo isn't a medical service and this isn't a diagnosis. For anything that doesn't settle, see a doctor or physio.")
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
            icon: "checkmark.circle.fill", color: TideTrain.positive,
            title: String(localized: "Load reduced 20%"),
            message: String(localized: "This exercise's remaining sets today are lighter. Stop again if it doesn't ease up.")
        ) {
            doneButton
        }
    }

    private func moderateOutcome(_ report: PainReport) -> some View {
        outcomeShell(
            icon: "arrow.triangle.2.circlepath", color: TideTrain.caution,
            title: String(localized: "Swap it or skip it"),
            message: String(localized: "Moderate pain — pick a pain-free alternative for the same muscle, or skip this exercise for today.")
        ) {
            VStack(spacing: Tide.s2) {
                if let message = swapFailedMessage {
                    Text(message)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.danger)
                        .multilineTextAlignment(.center)
                }
                if let plannedExercise, !swapChoices.isEmpty {
                    ForEach(Array(swapChoices.prefix(4)), id: \.id) { alt in
                        Button {
                            if viewModel.applyPainSwap(report, plannedExercise: plannedExercise, to: alt, modelContext: modelContext) {
                                dismiss()
                            } else {
                                swapFailedMessage = String(localized: "You've already logged a set on this one — swapping mid-exercise isn't safe. Skip it instead.")
                            }
                        } label: {
                            TrainRowLabel(
                                systemImage: "arrow.triangle.2.circlepath",
                                title: alt.name,
                                tint: TideTrain.caution
                            )
                            .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
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
                }
                .buttonStyle(.tideGlass)
            }
        }
    }

    private func severeOutcome(_ report: PainReport) -> some View {
        let canEnd = viewModel.canEndSessionForPain
        return outcomeShell(
            icon: "exclamationmark.octagon.fill", color: Tide.danger,
            title: String(localized: "Stop this exercise"),
            message: canEnd
                ? String(localized: "That's a lot of pain to push through. Consider ending the session — and if it doesn't settle down, get it looked at by a professional.")
                : String(localized: "That's a lot of pain to push through. Skip it today — and if it doesn't settle down, get it looked at by a professional.")
        ) {
            VStack(spacing: Tide.s2) {
                if canEnd {
                    Button(role: .destructive) {
                        dismiss()
                        // Sets logged → summary; none → session closes. The
                        // workout screen follows sessionState, not this sheet.
                        viewModel.endSessionDueToPain(report, plannedExercise: plannedExercise, modelContext: modelContext)
                    } label: {
                        Text("End the session")
                            .font(Tide.bodyStrong)
                            .frame(maxWidth: .infinity)
                            .frame(height: TideTrain.bigButton)
                            .foregroundStyle(Tide.ink)
                            .background(Tide.danger, in: .capsule)
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
                }
                .buttonStyle(.tideGlass)
            }
        }
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
        }
        .buttonStyle(.tideGlass)
    }

    private func outcomeShell(
        icon: String, color: Color, title: String, message: String,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        TrainSessionStateView(systemImage: icon, tint: color, title: title, message: message) {
            actions()
        }
    }
}
