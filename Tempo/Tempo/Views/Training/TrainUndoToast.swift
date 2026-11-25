//
// TrainUndoToast.swift
// Tempo
//
// The Undo toast for a workout that was just discarded. The logger has closed
// by then, so the toast sits on the page underneath it (Train home) and reads
// the offer from the view model (`discardUndo`). Undo brings the session back
// and the logger opens again by itself, the same way it does after a crash.
//

import SwiftData
import SwiftUI

// MARK: - DiscardedWorkoutToast

private struct DiscardedWorkoutToast: ViewModifier {
    @Bindable
    var viewModel: TrainingViewModel
    @Environment(\.modelContext)
    private var modelContext

    // Posted to the app shell's toast, which the tab on screen shows above the
    // tab bar: the logger can close onto any tab (Train, Today, a Move page).
    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.discardUndo?.id) { _, id in
                guard id != nil, let undo = viewModel.discardUndo else {
                    return
                }
                FuelLogToast.post(ToastData(
                    message: "Workout discarded",
                    style: .info,
                    actionTitle: "Undo"
                ) {
                    Task { @MainActor in
                        let restored = await viewModel.undoDiscardedWorkoutWhenSettled(undo, modelContext: modelContext)
                        viewModel.forgetDiscardedWorkout()
                        if !restored {
                            // Say so, rather than leave a dead button.
                            FuelLogToast.post(ToastData(message: "Can't undo that now", style: .warning))
                        }
                    }
                })
            }
            .task(id: viewModel.discardUndo?.id) {
                // The offer ends a moment after the toast does.
                guard viewModel.discardUndo != nil else {
                    return
                }
                try? await Task.sleep(for: .seconds(6))
                if !Task.isCancelled {
                    viewModel.forgetDiscardedWorkout()
                }
            }
    }
}

extension View {
    /// Shows the Undo toast when a workout is discarded from the logger.
    func discardedWorkoutUndoToast(_ viewModel: TrainingViewModel) -> some View {
        modifier(DiscardedWorkoutToast(viewModel: viewModel))
    }
}
