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
        TrainBanner(
            systemImage: "figure.walk.arrival",
            label: "Welcome back",
            tint: TideTrain.positive,
            title: "Pick up where you left off?",
            message: "Your trainer's program uses fixed weekdays. Continue the same program week you paused in, or just pick up from today's weekday."
        ) {
            Button {
                showOptions = true
            } label: {
                Text("Choose")
            }
            .buttonStyle(.trainBanner(tint: TideTrain.positive))
        }
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
