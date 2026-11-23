//
// MissedTrainerSessionCard.swift
// Tempo
//
// Fix #6 — fixed-mode-only banner: "Missed <session> — do it today?". Shown
// above Today's own content when the most recent trainer-program day (within
// the last week) wasn't completed and wasn't already legitimately overridden
// by a match or red recovery (`TrainingViewModel.missedFixedSession`).
// Self-contained so it can be dropped into TodayWorkoutView with a single
// line — see that file's `body` for the one-line insertion point.
//

import SwiftData
import SwiftUI

// MARK: - MissedTrainerSessionCard

struct MissedTrainerSessionCard: View {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext

    @State
    private var missed: TrainingViewModel.MissedTrainerSession?

    var body: some View {
        VStack(spacing: 0) {
            if let missed {
                card(for: missed)
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

    private func card(for missed: TrainingViewModel.MissedTrainerSession) -> some View {
        TrainBanner(
            systemImage: "exclamationmark.triangle.fill",
            label: "Missed on \(missed.date.formatted(.dateTime.weekday(.wide)))",
            tint: TideTrain.caution,
            title: missed.day.title ?? missed.day.workoutType.displayName,
            message: "Swap it in for today's session instead?"
        ) {
            Button {
                viewModel.swapInMissedSession(missed, modelContext: modelContext)
                HapticManager.selection()
                self.missed = nil
            } label: {
                Label("Do it today", systemImage: "arrow.uturn.left")
            }
            .buttonStyle(.trainBanner(tint: TideTrain.caution))
        }
    }

    /// Only worth offering while Today is still `.planned` (untouched) —
    /// once a session has started/finished, swapping in a different one
    /// would discard real progress.
    private func refresh() {
        guard viewModel.todayPlan?.status == .planned else {
            missed = nil
            return
        }
        missed = viewModel.missedFixedSession(modelContext: modelContext)
    }
}
