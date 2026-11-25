//
// ExerciseTechniqueViews.swift
// Tempo
//
// How the form guide (ExerciseTechnique) is shown: the lines shared by the
// exercise page and the workout, and the collapsed "Form" row on the set
// screen. The row stays one line tall until it is tapped, and it sits under
// the set card, so it is never between you and logging.
//

import SwiftUI

// MARK: - ExerciseTechniqueLines

/// The numbered cues, then the common mistakes.
struct ExerciseTechniqueLines: View {
    let technique: ExerciseTechnique

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            ForEach(Array(technique.cues.enumerated()), id: \.offset) { index, cue in
                HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                    Text("\(index + 1)")
                        .font(TideTrain.figure(.caption, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(minWidth: Tide.s4, alignment: .trailing)
                        .accessibilityHidden(true)
                    Text(cue)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Cue \(index + 1): \(cue)")
            }

            TrainPlanDivider()

            TideSectionLabel(title: String(localized: "Common mistakes"))

            ForEach(Array(technique.mistakes.enumerated()), id: \.offset) { _, mistake in
                HStack(alignment: .firstTextBaseline, spacing: Tide.s3) {
                    Image(systemName: "xmark")
                        .font(Tide.label)
                        .foregroundStyle(Tide.danger)
                        .frame(minWidth: Tide.s4, alignment: .trailing)
                        .accessibilityHidden(true)
                    Text(mistake)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Mistake: \(mistake)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - WorkoutFormRow

/// The form guide on the set screen. Collapsed it is a single row that shows
/// the first cue; one tap opens every cue and the common mistakes below the
/// set card.
struct WorkoutFormRow: View {
    let technique: ExerciseTechnique

    @State
    private var isOpen = false
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @Environment(\.dynamicTypeSize)
    private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Tide.s3) {
            Button(action: toggle) {
                header
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("workout-form-toggle")
            .accessibilityValue(isOpen ? String(localized: "state.open", defaultValue: "Open", comment: "Accessibility value: an expandable section is open") : String(localized: "Closed"))
            .accessibilityHint(isOpen ? String(localized: "Hides the form guide") : String(localized: "Shows the cues and common mistakes"))

            if isOpen {
                ExerciseTechniqueLines(technique: technique)
                    .transition(.opacity)
                    .accessibilityIdentifier("workout-form-lines")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tideCard(padding: Tide.s3, radius: Tide.tileRadius)
    }

    private var header: some View {
        HStack(spacing: Tide.s3) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(Tide.headline)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tide.hair) {
                TideLabel(String(localized: "Form"))
                if !isOpen, let first = technique.cues.first {
                    Text(first)
                        .font(Tide.caption)
                        .foregroundStyle(Tide.text2)
                        .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: Tide.s2)
            Image(systemName: "chevron.down")
                .font(Tide.label)
                .foregroundStyle(Tide.text3)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .accessibilityHidden(true)
        }
        .frame(minHeight: Tide.hit)
        .contentShape(.rect)
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : Tide.snap) {
            isOpen.toggle()
        }
    }
}
