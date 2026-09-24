//
// TrainerSessionCard.swift
// Tempo
//
// A trainer's session as written, on Today: blocks in order, each with its
// prescription (free-text detail for conditioning, sets × reps for lifts),
// effort, rest and notes.
//

import SwiftUI

struct TrainerSessionCard: View {
    let day: ProgramDay
    let heading: String

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
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.name)
                        .font(.tempoBody)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.tempoTextPrimary)
                    Text(trainerPrescription(block))
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let notes = block.notes {
                        Text(notes)
                            .font(.tempoCaption2)
                            .foregroundStyle(Color.tempoSignal)
                    }
                }
                .accessibilityElement(children: .combine)
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
