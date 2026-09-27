//
// WelcomeBackResumeCard.swift
// Tempo
//
// Pause/travel-pain feature — a fixed-mode pause's resume decision
// (shift-forward vs continue-from-today) must be RESOLVED, not just left to
// default silently once `plannedEndDate` passes and `PausedTrainingCard`
// disappears (`TrainingPauseSchedule.coveringPause` stops covering that day,
// but `TrainingPause.resumeDecision` stays nil until something records it —
// see `TrainingViewModel+Pause.pendingResumeDecision`). This card is that
// "something": shown above Today's normal content, same self-contained
// drop-in pattern as `MissedTrainerSessionCard.swift`, whenever a fixed-mode
// pause has ended but never got a decision.
//

import SwiftData
import SwiftUI

// MARK: - WelcomeBackResumeCard

struct WelcomeBackResumeCard: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext

    @State
    private var pending: TrainingPause?
    @State
    private var showOptions = false

    var body: some View {
        VStack(spacing: 0) {
            if let pending {
                card(for: pending)
            }
        }
        .task(id: viewModel.todayPlan?.id) {
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoWorkoutChanged)) { _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .tempoTrainingSettingsChanged)) { _ in
            refresh()
        }
    }

    private func card(for pause: TrainingPause) -> some View {
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.xs) {
                Image(systemName: "figure.walk.arrival")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoSuccess)
                Text("WELCOME BACK")
                    .font(.tempoCaption2.weight(.semibold))
                    .foregroundStyle(Color.tempoSuccess)
            }
            Text("Pick up where you left off?")
                .font(.tempoBodyBold)
                .foregroundStyle(Color.tempoTextPrimary)
            Text(
                "Your trainer's program uses fixed weekdays. Continue the same program week you paused in, or just pick up from today's weekday."
            )
            .font(.tempoFootnote)
            .foregroundStyle(Color.tempoTextSecondary)

            Button {
                showOptions = true
            } label: {
                Text("Choose")
                    .font(.tempoSubheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .background(Color.tempoSuccess.opacity(TempoOpacity.o15))
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .strokeBorder(Color.tempoSuccess.opacity(TempoOpacity.o15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .padding(.horizontal, TempoSpacing.lg)
        .confirmationDialog("Resume training?", isPresented: $showOptions, titleVisibility: .visible) {
            Button("Continue this week where I left off (shift program)") {
                resolve(decision: .shiftForward)
            }
            Button("Just continue from today") {
                resolve(decision: .continueFromToday)
            }
        }
    }

    private func resolve(decision: PauseResumeDecision) {
        guard let pending else {
            return
        }
        viewModel.resumePause(pending, decision: decision, modelContext: modelContext)
        self.pending = nil
    }

    private func refresh() {
        pending = viewModel.pendingResumeDecision(modelContext: modelContext)
    }
}
