//
// RestTimerView.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import SwiftUI

// MARK: - Rest Timer View

// Per MODULE_TRAINING.md Section 7 — Countdown rest timer between sets.
// Per STATE_MACHINES.md Section 1 — exercise.resting state.

struct RestTimerView: View {
    @Bindable
    var viewModel: TrainingViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: TempoSpacing.xl) {
                restBody
            }
            .padding(.vertical, TempoSpacing.xl)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .background(Color.tempoBgPrimary)
    }

    /// Whole seconds left — drives the end-of-rest color shift and pulse.
    private var secondsLeft: Int {
        Int(viewModel.restTimerRemaining.rounded(.up))
    }

    /// §11.6 — dial goes amber for the final 10s so the color itself says
    /// "get ready" without reading the number.
    private var ringColor: Color {
        secondsLeft <= 10 ? .tempoAmber : .tempoSignal
    }

    @ViewBuilder
    private var restBody: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(Color.tempoTextTertiary.opacity(0.2), lineWidth: 8)
                .frame(width: 200, height: 200)

            // Progress ring
            Circle()
                .trim(from: 0, to: viewModel.restTimerProgress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: viewModel.restTimerProgress)
                .animation(.easeInOut(duration: 0.4), value: secondsLeft <= 10)

            // Time display — digits roll instead of blinking, and the
            // final 5 seconds heartbeat-pulse the whole readout.
            VStack(spacing: TempoSpacing.xxs) {
                Text(viewModel.formattedRestTimer)
                    .font(.tempoDataLarge)
                    .foregroundStyle(secondsLeft <= 10 ? Color.tempoAmber : Color.tempoTextPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.3), value: viewModel.formattedRestTimer)

                Text("REST")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextTertiary)
            }
            .scaleEffect(secondsLeft <= 5 && secondsLeft > 0 && secondsLeft % 2 == 1 ? 1.08 : 1.0)
            .animation(.spring(duration: 0.5), value: secondsLeft)
        }

        // Inline "how was that set?" — edits the eagerly-created feedback
        // row save-on-change. Only for working sets (warmups have none).
        if viewModel.currentFeedback != nil {
            InlineSetFeedbackView(viewModel: viewModel)
        }

        // What you're resting toward. Between sets: name + next set.
        // Before the next exercise: name + full how-to so the user is never
        // surprised by an exercise they don't know.
        restPreview

        // Single control: end the rest early and start the next set/exercise.
        // (The old "+15s" button is gone; rest auto-advances anyway.)
        Button {
            viewModel.skipRest()
            HapticManager.notification(.success)
        } label: {
            Text(skipButtonTitle)
                .font(.tempoHeadline)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.tempoSignal)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxl, style: .continuous))
        }
        .padding(.horizontal, TempoSpacing.screenEdge)
    }

    // MARK: - Rest Preview

    /// Primary button title: contextual on whether the next thing is another
    /// set of the same exercise or a brand-new exercise.
    private var skipButtonTitle: String {
        viewModel.restContext.isExerciseTransition ? "Start Next Exercise →" : "Skip Rest →"
    }

    @ViewBuilder
    private var restPreview: some View {
        let ctx = viewModel.restContext
        if ctx.isExerciseTransition, let exercise = ctx.exercise {
            // Next exercise — name + how-to. NOT its own ScrollView: it is plain
            // content inside the single outer ScrollView so the whole rest page
            // scrolls as one unit (the inner scroll made this card bounce on its
            // own). Name matches the set-active header size.
            VStack(alignment: .leading, spacing: TempoSpacing.sm) {
                Text("UP NEXT")
                    .font(.tempoCaption2)
                    .foregroundStyle(Color.tempoTextTertiary)
                Text(exercise.name)
                    .font(.tempoTitle2)
                    .foregroundStyle(Color.tempoTextPrimary)

                if let instructions = exercise.instructions, !instructions.isEmpty {
                    Text(instructions)
                        .font(.tempoSubheadline)
                        .foregroundStyle(Color.tempoTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !exercise.cues.isEmpty {
                    VStack(alignment: .leading, spacing: TempoSpacing.xxs) {
                        ForEach(exercise.cues, id: \.self) { cue in
                            HStack(alignment: .top, spacing: TempoSpacing.xs) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.tempoCaption1)
                                    .foregroundStyle(Color.tempoSignal)
                                Text(cue)
                                    .font(.tempoFootnote)
                                    .foregroundStyle(Color.tempoTextSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, TempoSpacing.xxs)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TempoSpacing.md)
            .background(Color.tempoSurfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            .padding(.horizontal, TempoSpacing.screenEdge)
        } else if !ctx.label.isEmpty {
            // Between sets — compact label, no need to re-explain the movement.
            Text(ctx.label)
                .font(.tempoCaption1)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TempoSpacing.screenEdge)
        }
    }
}
