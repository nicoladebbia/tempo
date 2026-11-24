//
// TrainerSessionCard.swift
// Tempo
//
// A trainer's session as written, on Today: blocks in order, each with its
// prescription (free-text detail for conditioning, sets × reps for lifts),
// effort, rest and notes.
//
// Fix #7 — a conditioning block (day.isStrength == false) gets a "Log" action
// so shuttle times / duration / rounds / effort can be recorded against the
// trainer's own target, parsed from `detail` by ConditioningTargetParser. A
// lift block still just shows the prescription — it's logged through the
// normal gym set-by-set flow, not here.
//
// Guided run mode — a conditioning session also gets a primary "Start
// guided run" button that runs the whole session live (countdown, timed
// reps/rounds/continuous efforts, rest, cues) and logs every block through
// the same `logConditioningBlock` the per-block "Log" button uses. The
// per-block Log stays for after-the-fact manual entry.
//

import SwiftData
import SwiftUI

struct TrainerSessionCard: View {
    let day: ProgramDay
    let heading: String
    /// Needed only to log conditioning blocks — nil (or an empty session
    /// key) on any call site that doesn't want the Log action.
    var workoutPlanID: UUID?
    var programSessionKey: String?
    var viewModel: TrainingViewModel?
    /// The day's session is already marked done (a guided run was saved or a
    /// block logged): the start button gives way to a "Logged" row.
    var isDone = false

    @Environment(\.modelContext)
    private var modelContext

    @State
    private var loggingBlock: ProgramExercise?
    @State
    private var isPresentingGuidedRun = false

    private var canLog: Bool {
        !day.isStrength && workoutPlanID != nil && programSessionKey != nil && viewModel != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s2) {
            Text(heading).tideLabel()
            Text(day.title ?? day.workoutType.displayName)
                .font(Tide.title2)
                .foregroundStyle(Tide.text)
                .padding(.bottom, Tide.s1)
            ForEach(Array(day.exercises.enumerated()), id: \.element.id) { index, block in
                if index > 0 {
                    TrainPlanDivider()
                }
                blockRow(block)
            }
            if let notes = day.notes {
                Text(notes)
                    .font(Tide.caption)
                    .italic()
                    .foregroundStyle(Tide.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if canLog {
                if isDone {
                    loggedRow
                } else {
                    startGuidedRunButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        .sheet(item: $loggingBlock) { block in
            if let workoutPlanID, let programSessionKey, let viewModel {
                ConditioningLogSheet(
                    block: block,
                    workoutPlanID: workoutPlanID,
                    programSessionKey: programSessionKey,
                    viewModel: viewModel
                )
            }
        }
        .fullScreenCover(isPresented: $isPresentingGuidedRun) {
            if let workoutPlanID, let programSessionKey, let viewModel {
                GuidedRunView(
                    day: day,
                    workoutPlanID: workoutPlanID,
                    programSessionKey: programSessionKey,
                    heading: heading,
                    viewModel: viewModel
                )
            }
        }
    }

    private var loggedRow: some View {
        HStack(spacing: Tide.s1) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(TideTrain.positive)
            Text("Logged")
                .font(Tide.headline)
                .foregroundStyle(Tide.text)
        }
        .frame(maxWidth: .infinity, minHeight: Tide.fieldHeight)
        .padding(.top, Tide.s1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("guidedRunLoggedRow")
    }

    private var startGuidedRunButton: some View {
        Button {
            HapticManager.impact(.medium)
            isPresentingGuidedRun = true
        } label: {
            HStack(spacing: Tide.s1) {
                Image(systemName: "figure.run")
                Text("Start guided run")
            }
        }
        .buttonStyle(.tidePrimary)
        .padding(.top, Tide.s2)
        .accessibilityIdentifier("startGuidedRunButton")
    }

    private func blockRow(_ block: ProgramExercise) -> some View {
        VStack(alignment: .leading, spacing: Tide.hair) {
            HStack(alignment: .firstTextBaseline) {
                Text(block.name)
                    .font(Tide.bodyStrong)
                    .foregroundStyle(Tide.text)
                Spacer()
                if canLog {
                    Button {
                        HapticManager.selection()
                        loggingBlock = block
                    } label: {
                        Text("Log")
                            .font(Tide.bodyStrong)
                            .foregroundStyle(Color.accentColor)
                            .frame(minWidth: Tide.hit, minHeight: Tide.hit, alignment: .trailing)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(trainerPrescription(block))
                .font(Tide.caption)
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
            if let notes = block.notes {
                Text(notes)
                    .font(Tide.caption)
                    .foregroundStyle(Color.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if canLog, let viewModel, let programSessionKey {
                let results = viewModel.conditioningResults(forSessionKey: programSessionKey, modelContext: modelContext)
                    .filter { $0.blockID == block.id }
                if let latest = results.first {
                    resultLine(latest, block: block)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The compact "4/4 under 65\" · best 58\"" / "35' · 5.2 km · RPE 8" line
    /// under a logged block.
    private func resultLine(_ result: ConditioningBlockResult, block: ProgramExercise) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tide.s1) {
            Image(systemName: resultIcon(result))
                .font(Tide.caption)
                .foregroundStyle(resultColor(result))
                .accessibilityHidden(true)
            Text(resultText(result, block: block))
                .font(Tide.caption.weight(.semibold))
                .foregroundStyle(Tide.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, Tide.hair)
    }

    private func resultIcon(_ result: ConditioningBlockResult) -> String {
        switch result.targetMet {
        case true: "checkmark.circle.fill"
        case false: "xmark.circle.fill"
        case nil: "checkmark.seal.fill"
        }
    }

    private func resultColor(_ result: ConditioningBlockResult) -> Color {
        switch result.targetMet {
        case true: TideTrain.positive
        case false: Tide.danger
        case nil: Tide.text3
        }
    }

    private func resultText(_ result: ConditioningBlockResult, block: ProgramExercise) -> String {
        var parts: [String] = []
        if let times = result.repTimesSeconds, !times.isEmpty {
            let target = ConditioningTargetParser.parse(detail: block.detail)
            let best = ConditioningTargetEvaluator.bestTime(times)
            if case let .repsDistance(_, _, _, capSeconds) = target.kind, let capSeconds {
                let under = times.filter { $0 <= capSeconds }.count
                parts.append("\(under)/\(times.count) under \(formatSeconds(capSeconds))")
            } else {
                parts.append("\(times.count) reps")
            }
            if let best {
                parts.append("best \(formatSeconds(best))")
            }
        }
        if let duration = result.durationSeconds {
            parts.append(formatMinutesFromSeconds(duration))
        }
        if let distance = result.distanceMeters {
            parts.append(String(format: "%.1f km", distance / 1000))
        }
        if let rounds = result.roundsCompleted {
            parts.append("\(rounds) rounds")
        }
        if let rpe = result.rpe {
            parts.append("RPE \(rpe.formatted(.number.precision(.fractionLength(0 ... 1))))")
        }
        return parts.isEmpty ? "Logged" : parts.joined(separator: " · ")
    }

    private func formatSeconds(_ seconds: Double) -> String {
        seconds >= 60
            ? String(format: "%d:%02d\"", Int(seconds) / 60, Int(seconds) % 60)
            : "\(Int(seconds))\""
    }

    private func formatMinutesFromSeconds(_ seconds: Double) -> String {
        "\(Int((seconds / 60).rounded()))'"
    }

    private func trainerPrescription(_ block: ProgramExercise) -> String {
        var parts: [String] = []
        if let detail = block.detail, !detail.isEmpty {
            parts.append(detail)
        } else {
            let reps = block.repsHigh.map { "\(block.repsLow)-\($0)" } ?? "\(block.repsLow)"
            parts.append("\(block.sets) × \(reps)\(block.perSide == true ? " per side" : "")")
            if let pct = block.percentOf1RM {
                parts.append("\(Int((pct * 100).rounded()))%")
            }
        }
        if let rpe = block.rpe {
            parts.append("RPE \(rpe.formatted(.number.precision(.fractionLength(0 ... 1))))")
        }
        if let rest = block.restSeconds {
            parts.append(rest >= 60 && rest % 60 == 0 ? "rest \(rest / 60)'" : "rest \(rest)\"")
        }
        return parts.joined(separator: " · ")
    }
}
