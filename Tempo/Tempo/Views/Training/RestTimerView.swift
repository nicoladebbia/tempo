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
//
// The rest is a shader-lit ring that drains as the seconds pass. The last ten
// seconds turn it amber, so the colour says "get ready" before the number does.
// Under it, one pill says what you are resting toward; then the quick "how was
// that set" card; Skip Rest is the one filled button, at the bottom.

struct RestTimerView: View {
    @Bindable
    var viewModel: TrainingViewModel

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle)
    private var timeSize: CGFloat = TideTrainSession.restClock

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Tide.s5) {
                restBody
            }
            .padding(.vertical, Tide.s5)
            .padding(.horizontal, Tide.edge)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            skipButton
                .padding(.horizontal, Tide.edge)
                .padding(.bottom, Tide.s3)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: secondsLeft <= 3 && secondsLeft > 0 ? secondsLeft : 0)
    }

    /// Whole seconds left — drives the end-of-rest color shift and pulse.
    private var secondsLeft: Int {
        Int(viewModel.restTimerRemaining.rounded(.up))
    }

    private var endingSoon: Bool {
        secondsLeft <= 10
    }

    /// §11.6 — the ring goes amber for the final 10s.
    private var ringTint: Color? {
        endingSoon ? TideTrain.caution : nil
    }

    /// The lit part of the ring is what is LEFT of the rest.
    private var remainingFraction: Double {
        1 - viewModel.restTimerProgress
    }

    @ViewBuilder
    private var restBody: some View {
        TrainRing(
            progress: remainingFraction,
            tint: ringTint,
            diameter: viewModel.currentFeedback != nil ? TideTrainSession.restRingCompact : TideTrainSession.restRing
        ) {
            VStack(spacing: Tide.hair) {
                Text(viewModel.formattedRestTimer)
                    .font(Tide.numeral(min(timeSize, TideTrainSession.restClockCap)))
                    .foregroundStyle(endingSoon ? TideTrain.caution : Tide.text)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(reduceMotion ? nil : Tide.snap, value: viewModel.formattedRestTimer)
                    .lineLimit(1)
                    .minimumScaleFactor(TideTrainSession.clockShrink)
                Text("Rest").tideLabel()
            }
            .scaleEffect(!reduceMotion && secondsLeft <= 5 && secondsLeft > 0 && secondsLeft % 2 == 1 ? 1.06 : 1)
            .animation(reduceMotion ? nil : Tide.lively, value: secondsLeft)
        }
        .animation(reduceMotion ? nil : .linear(duration: 1), value: viewModel.restTimerProgress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rest")
        .accessibilityValue("\(secondsLeft) seconds left")

        // Between sets: one pill under the ring says what the rest leads to.
        if !viewModel.restContext.isExerciseTransition, !viewModel.restContext.label.isEmpty {
            Text(viewModel.restContext.label)
                .font(Tide.bodyStrong)
                .foregroundStyle(Tide.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Tide.s4)
                .padding(.vertical, Tide.s3)
                .glassEffect(.regular.tint(Tide.glassControl), in: .capsule)
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
    }

    // MARK: - Skip

    /// Single control: end the rest early and start the next set/exercise.
    /// (The old "+15s" button is gone; rest auto-advances anyway.)
    private var skipButton: some View {
        Button {
            viewModel.skipRest()
            HapticManager.notification(.success)
        } label: {
            Text(skipButtonTitle)
                .frame(minHeight: TideTrain.bigButton - Tide.s2)
        }
        .buttonStyle(.tidePrimary)
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
            // own).
            VStack(alignment: .leading, spacing: Tide.s3) {
                Text("Up next").tideLabel()
                HStack(spacing: Tide.s3) {
                    ExerciseImageView(exercise: exercise, style: .hero)
                        .frame(width: TideTrain.thumb, height: TideTrain.thumb)
                        .clipShape(RoundedRectangle(cornerRadius: Tide.controlRadius, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Tide.hair) {
                        Text(exercise.name)
                            .font(Tide.title2)
                            .foregroundStyle(Tide.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(exercise.muscleGroup.displayName)
                            .font(Tide.caption)
                            .foregroundStyle(Tide.text2)
                    }
                }

                if let instructions = exercise.instructions, !instructions.isEmpty {
                    Text(instructions)
                        .font(Tide.body)
                        .foregroundStyle(Tide.text2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !exercise.cues.isEmpty {
                    TrainSessionRule()
                    VStack(alignment: .leading, spacing: Tide.s2) {
                        ForEach(exercise.cues, id: \.self) { cue in
                            HStack(alignment: .top, spacing: Tide.s2) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(Tide.caption)
                                    .foregroundStyle(TideTrain.positive)
                                    .accessibilityHidden(true)
                                Text(cue)
                                    .font(Tide.caption)
                                    .foregroundStyle(Tide.text2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .tideCard(padding: Tide.s4, radius: Tide.tileRadius)
        }
    }
}
