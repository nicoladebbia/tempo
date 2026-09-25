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

    @Environment(\.modelContext)
    private var modelContext

    @State
    private var loggingBlock: ProgramExercise?

    private var canLog: Bool {
        !day.isStrength && workoutPlanID != nil && programSessionKey != nil && viewModel != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text(heading)
                .font(.tempoCaption2)
                .fontWeight(.bold)
                .foregroundStyle(Color.tempoTextTertiary)
            Text((day.title ?? day.workoutType.displayName).uppercased())
                .font(.tempoHeadline)
                .foregroundStyle(Color.tempoTextPrimary)
            ForEach(day.exercises) { block in
                blockRow(block)
            }
            if let notes = day.notes {
                Text(notes)
                    .font(.tempoCaption1)
                    .italic()
                    .foregroundStyle(Color.tempoTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
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
    }

    private func blockRow(_ block: ProgramExercise) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(block.name)
                    .font(.tempoBody)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.tempoTextPrimary)
                Spacer()
                if canLog {
                    Button {
                        HapticManager.selection()
                        loggingBlock = block
                    } label: {
                        Text("Log")
                            .font(.tempoCaption1)
                            .fontWeight(.bold)
                            .foregroundStyle(Color.tempoSignal)
                    }
                }
            }
            Text(trainerPrescription(block))
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let notes = block.notes {
                Text(notes)
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoSignal)
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
        HStack(spacing: TempoSpacing.xs) {
            Image(systemName: resultIcon(result))
                .foregroundStyle(resultColor(result))
            Text(resultText(result, block: block))
                .font(.tempoCaption2)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextSecondary)
        }
        .padding(.top, 2)
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
        case true: Color.tempoRecoveryGreen
        case false: Color.tempoError
        case nil: Color.tempoTextTertiary
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
