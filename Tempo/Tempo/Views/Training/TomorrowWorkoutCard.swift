//
// TomorrowWorkoutCard.swift
// Tempo
//
// Tomorrow's workout under today's content: type, exercises with
// sets x reps @ weight, and the rebalance note when an extra gym session
// today reshaped it. Read-only — see TrainingViewModel+TomorrowPreview.
//

import SwiftUI

struct TomorrowWorkoutCard: View {
    let preview: TomorrowPreview

    var body: some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            Text("TOMORROW · \(preview.type.displayName.uppercased())")
                .font(.tempoCaption1)
                .fontWeight(.semibold)
                .foregroundStyle(Color.tempoTextTertiary)

            if let note = preview.note {
                Label(note, systemImage: "arrow.triangle.2.circlepath")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoWarning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("tomorrow.note")
            }

            if preview.rows.isEmpty {
                Text(emptyLine)
                    .font(.tempoSubheadline)
                    .foregroundStyle(Color.tempoTextSecondary)
            } else {
                VStack(spacing: TempoSpacing.xs) {
                    ForEach(preview.rows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.sm) {
                            Text(row.name)
                                .font(.tempoBody)
                                .foregroundStyle(Color.tempoTextPrimary)
                                .lineLimit(1)
                            Spacer(minLength: TempoSpacing.sm)
                            Text(row.detail(unit: preview.unit))
                                .font(.tempoCaption1)
                                .foregroundStyle(Color.tempoTextSecondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.cardPadding)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tomorrow.card")
    }

    private var emptyLine: String {
        switch preview.type {
        case .rest: "Rest. Sleep, eat, come back sharp."
        case .football: "Football. Show up ready."
        default: "\(preview.type.displayName). Details land when the day starts."
        }
    }
}
