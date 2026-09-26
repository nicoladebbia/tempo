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
        VStack(alignment: .leading, spacing: TempoSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: TempoSpacing.xs) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.tempoCaption1)
                    .foregroundStyle(Color.tempoWarning)
                    .accessibilityHidden(true)
                Text("MISSED ON \(missed.date.formatted(.dateTime.weekday(.wide)).uppercased())")
                    .font(.tempoCaption2.weight(.semibold))
                    .foregroundStyle(Color.tempoWarning)
            }

            Text(missed.day.title ?? missed.day.workoutType.displayName)
                .font(.tempoBodyBold)
                .foregroundStyle(Color.tempoTextPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Swap it in for today's session instead?")
                .font(.tempoFootnote)
                .foregroundStyle(Color.tempoTextSecondary)

            Button {
                viewModel.swapInMissedSession(missed, modelContext: modelContext)
                HapticManager.selection()
                self.missed = nil
            } label: {
                Label("Do it today", systemImage: "arrow.uturn.left")
                    .font(.tempoSubheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .foregroundStyle(Color.tempoTextPrimary)
                    .background(Color.tempoWarning.opacity(TempoOpacity.o15))
                    .clipShape(RoundedRectangle(cornerRadius: TempoRadius.lg, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, TempoSpacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TempoSpacing.md)
        .background(Color.tempoSurfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous)
                .strokeBorder(Color.tempoWarning.opacity(TempoOpacity.o15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: TempoRadius.xxxl, style: .continuous))
        .padding(.horizontal, TempoSpacing.lg)
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
