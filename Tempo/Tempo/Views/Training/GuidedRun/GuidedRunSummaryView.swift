//
// GuidedRunSummaryView.swift
// Tempo
//
// Guided run mode — the finish screen: per block, rep times with ✓/✗ and
// best/avg, or distance/duration/pace; one RPE + notes for the session.
// Save calls the EXISTING `TrainingViewModel.logConditioningBlock` once per
// block (via GuidedRunSummaryBuilder) so History, the trainer report,
// completion, Dashboard Move and Week Plan all update through the paths
// they already use — never a parallel completion flag. "Discard" throws the
// whole session away with nothing persisted.
//
// Optional (§8): when the session tracked any GPS distance, best-effort
// saves an HKWorkout via the EXISTING HealthKitService.writeWorkout — no
// new entitlements, and a failure here never blocks the log save.
//

import SwiftData
import SwiftUI

struct GuidedRunSummaryView: View {
    let plan: GuidedRunPlan
    let results: [UUID: GuidedRunBlockRecord]
    let workoutPlanID: UUID
    let programSessionKey: String
    var viewModel: TrainingViewModel
    let onDone: () -> Void
    let onDiscard: () -> Void

    @Environment(\.modelContext)
    private var modelContext

    @State
    private var rpe: Int?
    @State
    private var notes = ""
    @State
    private var isSaving = false
    @State
    private var showDiscardConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TempoSpacing.xxl) {
                    header
                    ForEach(plan.blocks) { block in
                        blockSummary(block)
                    }
                    rpeSection
                    notesSection
                }
                .padding(TempoSpacing.screenEdge)
            }
            .background(Color.tempoBgPrimary)
            .navigationTitle("Session Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { showDiscardConfirm = true }
                        .foregroundStyle(Color.tempoError)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .fontWeight(.bold)
                    .disabled(isSaving || loggableInputs.isEmpty)
                    .accessibilityIdentifier("guidedRunSaveButton")
                }
            }
            .confirmationDialog(
                "Discard this session?",
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { onDiscard() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("Nothing will be logged — reps, times and distance are lost.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
            Text("SESSION COMPLETE")
                .font(.tempoDrillLabel)
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoSignal)
            Text("Here's what you put in.")
                .font(.tempoTitle2)
                .foregroundStyle(Color.tempoTextPrimary)
        }
    }

    // MARK: - Per-block summary

    private func blockSummary(_ block: GuidedRunBlock) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(block.name)
                    .font(.tempoHeadline)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                if let met = targetMet(block) {
                    Image(systemName: met ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(met ? Color.tempoRecoveryGreen : Color.tempoError)
                }
            }
            Text(block.trainerText)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)

            if let record = results[block.id] {
                blockDetail(block, record: record)
            } else {
                Text("Skipped — not started")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
        }
        .padding(TempoSpacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
    }

    @ViewBuilder
    private func blockDetail(_ block: GuidedRunBlock, record: GuidedRunBlockRecord) -> some View {
        if !record.repTimesSeconds.isEmpty {
            repTimesGrid(block, record: record)
        } else if record.roundsCompleted > 0 {
            Text("\(record.roundsCompleted) rounds completed")
                .font(.tempoBody)
                .foregroundStyle(Color.tempoTextPrimary)
        } else if record.durationSeconds != nil || record.distanceMeters != nil {
            continuousSummary(record)
        }
        if record.skippedCount > 0 {
            Text("\(record.skippedCount) skipped")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    private func repTimesGrid(_ block: GuidedRunBlock, record: GuidedRunBlockRecord) -> some View {
        let capSeconds: Double? = {
            if case let .repsDistance(_, _, _, cap) = block.target.kind {
                return cap
            }
            return nil
        }()
        let checks = record.repChecks(capSeconds: capSeconds)
        return VStack(alignment: .leading, spacing: TempoSpacing.xs) {
            ForEach(Array(record.repTimesSeconds.enumerated()), id: \.offset) { index, time in
                HStack {
                    Text("Rep \(index + 1)")
                        .font(.tempoBody)
                        .foregroundStyle(Color.tempoTextSecondary)
                    Spacer()
                    Text(GuidedRunFormatting.repTime(time))
                        .font(.tempoDataMedium)
                        .monospacedDigit()
                        .foregroundStyle(Color.tempoTextPrimary)
                    if let check = checks[index] {
                        Image(systemName: check ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(check ? Color.tempoRecoveryGreen : Color.tempoError)
                    }
                }
            }
            HStack(spacing: TempoSpacing.md) {
                if let best = record.bestRepSeconds {
                    Text("Best \(GuidedRunFormatting.repTime(best))")
                }
                if let avg = record.averageRepSeconds {
                    Text("Avg \(GuidedRunFormatting.repTime(avg))")
                }
            }
            .font(.tempoCaption1)
            .fontWeight(.semibold)
            .foregroundStyle(Color.tempoTextTertiary)
        }
    }

    private func continuousSummary(_ record: GuidedRunBlockRecord) -> some View {
        HStack(spacing: TempoSpacing.md) {
            if let duration = record.durationSeconds {
                Text(GuidedRunFormatting.clock(duration))
            }
            if let distance = record.distanceMeters, distance > 0 {
                Text(GuidedRunFormatting.distance(meters: distance, useMiles: false))
                if let duration = record.durationSeconds, duration > 0 {
                    Text(GuidedRunFormatting.pace(secondsPerKm: (duration / distance) * 1000, useMiles: false) ?? "")
                }
            }
        }
        .font(.tempoDataMedium)
        .foregroundStyle(Color.tempoTextPrimary)
    }

    private func targetMet(_ block: GuidedRunBlock) -> Bool? {
        guard let record = results[block.id] else {
            return nil
        }
        return ConditioningTargetEvaluator.targetMet(
            target: block.target,
            repTimesSeconds: record.repTimesSeconds.isEmpty ? nil : record.repTimesSeconds,
            durationSeconds: record.durationSeconds,
            distanceMeters: record.distanceMeters,
            roundsCompleted: record.roundsCompleted > 0 ? record.roundsCompleted : nil
        )
    }

    // MARK: - RPE + notes

    private var rpeSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionLabel("EFFORT (RPE)")
            HStack(spacing: TempoSpacing.xs) {
                ForEach(1 ... 10, id: \.self) { value in
                    Button {
                        HapticManager.selection()
                        rpe = value
                    } label: {
                        Text("\(value)")
                            .font(.tempoCaption1)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(rpe == value ? Color.tempoSignal : Color.tempoBgSecondary)
                            .foregroundStyle(rpe == value ? Color.tempoBone : Color.tempoTextPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.sm, style: .continuous))
                    }
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            sectionLabel("NOTES")
            TextField("How did it feel?", text: $notes, axis: .vertical)
                .font(.tempoBody)
                .lineLimit(2 ... 4)
                .padding(TempoSpacing.inputHorizontal)
                .background(Color.tempoBgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.md, style: .continuous))
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.tempoCaption2)
            .fontWeight(.bold)
            .foregroundStyle(Color.tempoTextTertiary)
    }

    // MARK: - Save

    private var loggableInputs: [GuidedRunSummaryBuilder.BlockLogInput] {
        GuidedRunSummaryBuilder.blockInputs(
            plan: plan,
            results: results,
            rpe: rpe.map(Double.init),
            notes: notes.isEmpty ? nil : notes
        )
    }

    private func save() {
        isSaving = true
        let inputs = loggableInputs
        for input in inputs {
            viewModel.logConditioningBlock(
                workoutPlanID: workoutPlanID,
                programSessionKey: programSessionKey,
                blockID: input.blockID,
                detail: input.detail,
                repTimesSeconds: input.repTimesSeconds,
                durationSeconds: input.durationSeconds,
                distanceMeters: input.distanceMeters,
                roundsCompleted: input.roundsCompleted,
                rpe: input.rpe,
                notes: input.notes,
                // Distinct from ConditioningLogSheet's "manual" — this was
                // timed/tracked live by the guided-run engine, not typed
                // after the fact (see ConditioningBlockResult.source).
                source: "guided_run",
                modelContext: modelContext
            )
        }
        HapticManager.notification(.success)
        saveToHealthIfPossible()
        isSaving = false
        onDone()
    }

    /// Best-effort only — a distance/duration total across every tracked
    /// block, saved as one running workout. Never blocks or fails the log
    /// save above.
    private func saveToHealthIfPossible() {
        let totalDuration = results.values.compactMap(\.durationSeconds).reduce(0, +)
        let totalDistance = results.values.compactMap(\.distanceMeters).reduce(0, +)
        guard totalDuration > 0 else {
            return
        }
        let end = Date()
        let sample = WorkoutSample(
            startDate: end.addingTimeInterval(-totalDuration),
            endDate: end,
            workoutType: "running",
            durationMinutes: totalDuration / 60,
            activeCalories: 0,
            averageHeartRate: nil,
            maxHeartRate: nil,
            distanceMeters: totalDistance > 0 ? totalDistance : nil
        )
        Task {
            try? await viewModel.healthKit.writeWorkout(sample)
        }
    }
}
