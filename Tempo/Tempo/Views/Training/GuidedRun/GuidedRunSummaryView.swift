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
    /// Real run span from the session (nil if no step ever started).
    var startedAt: Date?
    var endedAt: Date?
    let workoutPlanID: UUID
    let programSessionKey: String
    var viewModel: TrainingViewModel
    let onDone: () -> Void
    let onDiscard: () -> Void

    @Environment(\.modelContext)
    private var modelContext
    @Query
    private var userSettings: [UserSettings]

    @State
    private var rpe: Int?
    @State
    private var notes = ""
    @State
    private var isSaving = false
    @State
    private var showDiscardConfirm = false
    @FocusState
    private var notesFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Tide.s5) {
                    header
                    ForEach(plan.blocks) { block in
                        blockSummary(block)
                    }
                    rpeSection
                    notesSection
                }
                .padding(.horizontal, Tide.edge)
                .padding(.vertical, Tide.s3)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaBar(edge: .bottom) {
                saveButton
                    .padding(.horizontal, Tide.edge)
                    .padding(.bottom, Tide.s3)
            }
            .trainSheetRoot()
            .navigationTitle("Session Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { showDiscardConfirm = true }
                        .foregroundStyle(Tide.danger)
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
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Tide.s4) {
            VStack(alignment: .leading, spacing: Tide.hair) {
                Text("Session complete")
                    .font(Tide.label)
                    .foregroundStyle(Color.accentColor)
                Text("Here's what you put in.")
                    .font(Tide.title2)
                    .foregroundStyle(Tide.text)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            // The whole session at a glance: how long, how far, how much of it.
            HStack(alignment: .top, spacing: Tide.s4) {
                if let startedAt, let endedAt, endedAt > startedAt {
                    TrainStat(value: GuidedRunFormatting.clock(endedAt.timeIntervalSince(startedAt)), label: "Time")
                }
                TrainStat(value: "\(results.count)/\(plan.blocks.count)", label: "Blocks")
                if totalDistance > 0 {
                    TrainStat(value: GuidedRunFormatting.distance(meters: totalDistance, useMiles: useMiles), label: "Distance")
                }
            }
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }

    private var totalDistance: Double {
        results.values.compactMap(\.distanceMeters).reduce(0, +)
    }

    // MARK: - Per-block summary

    private func blockSummary(_ block: GuidedRunBlock) -> some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            HStack(alignment: .firstTextBaseline) {
                Text(block.name)
                    .font(Tide.headline)
                    .foregroundStyle(Tide.text)
                Spacer(minLength: Tide.s2)
                if let met = targetMet(block) {
                    Image(systemName: met ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(met ? TideTrain.positive : Tide.danger)
                        .accessibilityLabel(met ? "Target met" : "Target missed")
                }
            }
            Text(block.trainerText)
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)

            if let record = results[block.id] {
                blockDetail(block, record: record)
            } else {
                Text("Skipped — not started")
                    .font(Tide.caption)
                    .foregroundStyle(Tide.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
    }

    @ViewBuilder
    private func blockDetail(_ block: GuidedRunBlock, record: GuidedRunBlockRecord) -> some View {
        if !record.repTimesSeconds.isEmpty {
            repTimesGrid(block, record: record)
        } else if record.roundsCompleted > 0 {
            Text("\(record.roundsCompleted) rounds completed")
                .font(Tide.body)
                .foregroundStyle(Tide.text)
        } else if record.durationSeconds != nil || record.distanceMeters != nil {
            continuousSummary(record)
        }
        if record.skippedCount > 0 {
            Text("\(record.skippedCount) skipped")
                .font(Tide.caption)
                .foregroundStyle(Tide.text3)
        }
        if let avg = record.avgHeartRateBPM {
            HStack(spacing: Tide.s1) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(Tide.danger)
                Text("Avg \(Int(avg.rounded())) bpm")
                if let max = record.maxHeartRateBPM {
                    Text("· Max \(Int(max.rounded())) bpm")
                }
            }
            .font(Tide.caption)
            .foregroundStyle(Tide.text3)
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
        return VStack(alignment: .leading, spacing: Tide.s1) {
            ForEach(Array(record.repTimesSeconds.enumerated()), id: \.offset) { index, time in
                HStack {
                    Text("Rep \(index + 1)")
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                    Spacer()
                    Text(GuidedRunFormatting.repTime(time))
                        .font(TideTrain.figure(.headline))
                        .monospacedDigit()
                        .foregroundStyle(Tide.text)
                    if let check = checks[index] {
                        Image(systemName: check ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(check ? TideTrain.positive : Tide.danger)
                    }
                }
            }
            HStack(spacing: Tide.s3) {
                if let best = record.bestRepSeconds {
                    Text("Best \(GuidedRunFormatting.repTime(best))")
                }
                if let avg = record.averageRepSeconds {
                    Text("Avg \(GuidedRunFormatting.repTime(avg))")
                }
            }
            .font(Tide.caption)
            .fontWeight(.semibold)
            .foregroundStyle(Tide.text2)
        }
    }

    private var useMiles: Bool {
        GuidedRunFormatting.useMiles(weightUnit: userSettings.first?.weightUnit)
    }

    private func continuousSummary(_ record: GuidedRunBlockRecord) -> some View {
        HStack(spacing: Tide.s3) {
            if let duration = record.durationSeconds {
                Text(GuidedRunFormatting.clock(duration))
            }
            if let distance = record.distanceMeters, distance > 0 {
                Text(GuidedRunFormatting.distance(meters: distance, useMiles: useMiles))
                if let duration = record.durationSeconds, duration > 0 {
                    Text(GuidedRunFormatting.pace(secondsPerKm: (duration / distance) * 1000, useMiles: useMiles) ?? "")
                }
            }
        }
        .font(TideTrain.figure(.headline))
        .foregroundStyle(Tide.text)
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
        VStack(alignment: .leading, spacing: Tide.s2) {
            sectionLabel("Effort (RPE)")
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Tide.s2), count: 5),
                spacing: Tide.s2
            ) {
                ForEach(1 ... 10, id: \.self) { value in
                    Button {
                        HapticManager.selection()
                        rpe = value
                    } label: {
                        Text("\(value)")
                            .font(TideTrain.figure(.title3, weight: .semibold))
                    }
                    .buttonStyle(.trainChoice(isSelected: rpe == value))
                }
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            sectionLabel("Notes")
            TextField("How did it feel?", text: $notes, axis: .vertical)
                .font(Tide.body)
                .lineLimit(2 ... 4)
                .focused($notesFocused)
                .foregroundStyle(Tide.text)
                .tideFieldSurface(focused: notesFocused)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).tideLabel()
    }

    /// Save sits at the bottom, under the thumb. Disabled until there is
    /// something to log.
    private var saveButton: some View {
        Button {
            save()
        } label: {
            Group {
                if isSaving {
                    ProgressView()
                } else {
                    Text("Save")
                }
            }
            .frame(minHeight: TideTrain.bigButton - Tide.s2)
        }
        .buttonStyle(.tidePrimary)
        .disabled(isSaving || loggableInputs.isEmpty)
        .accessibilityIdentifier("guidedRunSaveButton")
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
                avgHeartRateBPM: input.avgHeartRateBPM,
                maxHeartRateBPM: input.maxHeartRateBPM,
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
        // Apple Watch run mode — a simple session-wide average/max across
        // every block that streamed HR, good enough for one summary
        // HKWorkout row (per-block detail lives on each ConditioningBlockResult).
        let allSamples = results.values.flatMap(\.heartRateSamplesBPM)
        let avgHeartRate = allSamples.isEmpty ? nil : allSamples.reduce(0, +) / Double(allSamples.count)
        let maxHeartRate = allSamples.max()
        let span = GuidedRunHealthSpan.resolve(
            startedAt: startedAt, endedAt: endedAt, trackedSeconds: totalDuration, now: Date()
        )
        let sample = WorkoutSample(
            startDate: span.start,
            endDate: span.end,
            workoutType: "running",
            durationMinutes: span.end.timeIntervalSince(span.start) / 60,
            activeCalories: 0,
            averageHeartRate: avgHeartRate,
            maxHeartRate: maxHeartRate,
            distanceMeters: totalDistance > 0 ? totalDistance : nil
        )
        Task {
            try? await viewModel.healthKit.writeWorkout(sample)
        }
    }
}

// MARK: - GuidedRunHealthSpan

/// The time span written to Apple Health for a guided run: the session's real
/// start/end when known (the summary can sit open for minutes before Save, so
/// "now" is not the end), else the tracked block time ending at the finish.
enum GuidedRunHealthSpan {
    static func resolve(
        startedAt: Date?, endedAt: Date?, trackedSeconds: Double, now: Date
    ) -> (start: Date, end: Date) {
        let end = endedAt ?? now
        if let startedAt, startedAt < end {
            return (startedAt, end)
        }
        return (end.addingTimeInterval(-max(1, trackedSeconds)), end)
    }
}
