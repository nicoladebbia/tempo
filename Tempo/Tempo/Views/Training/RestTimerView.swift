import SwiftUI

// MARK: - Rest Timer View
// Per MODULE_TRAINING.md Section 7 — Countdown rest timer between sets.
// Per STATE_MACHINES.md Section 1 — exercise.resting state.

struct RestTimerView: View {

    @Bindable var viewModel: TrainingViewModel

    var body: some View {
        VStack(spacing: TempoSpacing.xxl) {
            Spacer()

            // Countdown circle
            // Per MODULE_TRAINING.md — 200pt countdown circle
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.tempoTextTertiary.opacity(0.2), lineWidth: 8)
                    .frame(width: 200, height: 200)

                // Progress ring
                Circle()
                    .trim(from: 0, to: viewModel.restTimerProgress)
                    .stroke(Color.tempoSignal, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 200, height: 200)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: viewModel.restTimerProgress)

                // Time display
                VStack(spacing: TempoSpacing.xxs) {
                    Text(viewModel.formattedRestTimer)
                        .font(.tempoDataLarge)
                        .foregroundStyle(Color.tempoTextPrimary)
                        .monospacedDigit()

                    Text("REST")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }

            // Next exercise preview
            if let exercise = viewModel.currentExercise?.exercise {
                VStack(spacing: TempoSpacing.xs) {
                    Text("Current: \(exercise.name)")
                        .font(.tempoCaption1)
                        .foregroundStyle(Color.tempoTextSecondary)

                    Text(viewModel.setCountText)
                        .font(.tempoCaption2)
                        .foregroundStyle(Color.tempoTextTertiary)
                }
            }

            // Skip Rest button
            Button {
                viewModel.skipRest()
            } label: {
                Text("SKIP REST")
                    .font(.tempoHeadline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(Color.tempoTextSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous)
                            .stroke(Color.tempoTextTertiary, lineWidth: 1)
                    )
            }
            .padding(.horizontal, TempoSpacing.screenEdge)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.tempoBgPrimary)
    }
}
