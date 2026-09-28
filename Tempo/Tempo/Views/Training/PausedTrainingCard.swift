//
// PausedTrainingCard.swift
// Tempo
//
// Pause/travel-pain feature — Today's calm "Paused — recover" card, shown
// INSTEAD of the normal workout content while today is covered by a
// `TrainingPause` and today's plan is still untouched (`.planned` — a
// started/completed session is sacred and is never interrupted by a pause
// that started later, same invariant `TrainingPauseSchedule.apply` itself
// enforces). Self-contained, same drop-in pattern as
// `MissedTrainerSessionCard.swift`/`WeeklyUploadPromptCard.swift` — see
// `TodayWorkoutView.swift`'s body for the one-line insertion point.
//

import SwiftData
import SwiftUI

// MARK: - PausedTrainingCard

struct PausedTrainingCard: View {
    @Bindable
    var viewModel: TrainingViewModel
    let pause: TrainingPause
    @Environment(\.modelContext)
    private var modelContext
    @State
    private var showResumeOptions = false

    var body: some View {
        VStack(alignment: .center, spacing: TempoSpacing.md) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.tempoSuccess)
                .accessibilityHidden(true)

            Text("PAUSED")
                .font(.tempoCaption2.weight(.bold))
                .tracking(TempoTracking.drillLabel)
                .foregroundStyle(Color.tempoTextSecondary)

            Text(title)
                .font(.tempoTitle3)
                .foregroundStyle(Color.tempoTextPrimary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.tempoFootnote)
                .foregroundStyle(Color.tempoTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                showResumeOptions = true
            } label: {
                Text("Resume now")
                    .font(.tempoSubheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(Color.tempoTextInverse)
                    .background(Color.tempoSuccess)
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, TempoSpacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(TempoSpacing.xl)
        .background(Color.tempoSurfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .tempoShadow(.card)
        .confirmationDialog("Resume training?", isPresented: $showResumeOptions, titleVisibility: .visible) {
            if needsFixedModeDecision {
                Button("Continue this week where I left off (shift program)") {
                    resume(decision: .shiftForward)
                }
                Button("Just continue from today") {
                    resume(decision: .continueFromToday)
                }
            } else {
                Button("Resume now") {
                    resume(decision: .continueFromToday)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if needsFixedModeDecision {
                Text(
                    "Your trainer's program uses fixed weekdays. Pick up the same week you paused in, or just continue from today's weekday."
                )
            }
        }
    }

    private var needsFixedModeDecision: Bool {
        pause.scheduleModeAtPauseTyped == .fixed
    }

    private var title: String {
        switch pause.reason {
        case .sick: "Recover — training is on hold"
        case .injured: "Recover — training is on hold"
        case .travel: "Away — training is on hold"
        case .other: "Training is on hold"
        }
    }

    private var subtitle: String {
        if let end = pause.plannedEndDate {
            return "Back on \(end.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))."
        }
        return "Resume whenever you're ready."
    }

    private func resume(decision: PauseResumeDecision) {
        viewModel.resumePause(pause, decision: decision, modelContext: modelContext)
        HapticManager.selection()
    }
}
