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
        HStack(alignment: .top, spacing: TempoSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.tempoWarning)
                .font(.tempoBody)

            VStack(alignment: .leading, spacing: 2) {
                Text("Missed \(missed.day.title ?? missed.day.workoutType.displayName)")
                    .font(.tempoBodyBold)
                    .foregroundStyle(Color.tempoTextPrimary)
                Text("From \(missed.date.formatted(date: .abbreviated, time: .omitted)). Swap it in for today?")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoTextSecondary)
            }

            Spacer()

            Button("Do it today") {
                viewModel.swapInMissedSession(missed, modelContext: modelContext)
                HapticManager.selection()
                self.missed = nil
            }
            .buttonStyle(.tempoSecondary)
            .font(.tempoCaption1.weight(.semibold))
        }
        .padding(TempoSpacing.cardPaddingCompact)
        .background(Color.tempoWarning.opacity(TempoOpacity.o15))
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xl))
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
