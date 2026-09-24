//
// ActiveWorkoutView+PerSide.swift
// Tempo
//
// Fix #9 — per-side (unilateral) set logging split out of ActiveWorkoutView
// itself to keep that file under the SwiftLint file_length cap: the derived
// state this feature needs, plus the small "log sides separately" control.
//

import SwiftUI

extension ActiveWorkoutView {
    /// True when the current exercise is a unilateral, per-side trainer
    /// prescription ("SA DB Row 3x8 each").
    var isPerSideExercise: Bool {
        viewModel.currentExercise?.perSide == true
    }

    /// Non-nil only when the athlete opted into logging this per-side set's
    /// two sides separately; nil (the default) means `inputReps` alone
    /// describes both sides, same as any other set.
    var splitLeftReps: Int? {
        guard isPerSideExercise, logRepsSeparately, !currentSetIsWarmup else {
            return nil
        }
        return Int(inputReps)
    }

    var splitRightReps: Int? {
        guard isPerSideExercise, logRepsSeparately, !currentSetIsWarmup else {
            return nil
        }
        return Int(inputRepsRight)
    }
}

// MARK: - PerSideRepsControl

/// Fix #9 — lightweight L/R split control for a per-side set: a toggle that
/// reveals a second RIGHT reps stepper when the athlete wants to log an
/// uneven set (e.g. L 8 / R 7) instead of one count applying to both sides.
struct PerSideRepsControl: View {
    @Binding
    var left: Double
    @Binding
    var right: Double
    @Binding
    var splitEnabled: Bool

    var body: some View {
        Button {
            splitEnabled.toggle()
            if splitEnabled {
                right = left
            }
            HapticManager.selection()
        } label: {
            Label(
                splitEnabled ? "Same both sides" : "Log sides separately",
                systemImage: splitEnabled ? "arrow.triangle.merge" : "arrow.left.arrow.right"
            )
            .font(.tempoCaption2)
            .foregroundStyle(Color.tempoTextSecondary)
        }
        .buttonStyle(.plain)

        if splitEnabled {
            Text("REPS — RIGHT")
                .font(.tempoCaption2)
                .foregroundStyle(Color.tempoTextTertiary)
            NumberStepperView(
                value: $right,
                range: 1 ... 100,
                step: 1,
                format: "%.0f",
                unit: "reps / side"
            )
        }
    }
}
