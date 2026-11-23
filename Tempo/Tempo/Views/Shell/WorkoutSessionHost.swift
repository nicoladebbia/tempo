//
// WorkoutSessionHost.swift
// Tempo
//
// The workout screens, hosted once for the whole app. Today, the Train tab
// and the Move detail all start the shared session
// (`WorkoutSessionCoordinator`); this is the only place that presents it.
//

import SwiftData
import SwiftUI

struct WorkoutSessionHost: ViewModifier {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext

    func body(content: Content) -> some View {
        @Bindable
        var session = services.workoutSession
        let viewModel = session.viewModel
        return content
            .sensoryFeedback(.success, trigger: session.starts)
            .fullScreenCover(isPresented: $session.showActiveWorkout) {
                NavigationStack {
                    ActiveWorkoutView(viewModel: viewModel)
                }
            }
            .fullScreenCover(isPresented: $session.showSummary, onDismiss: {
                session.showSummary = false
                // However the summary closed, its feedback is now final.
                viewModel.applyPendingLearning(modelContext: modelContext, summaryClosed: true)
            }) {
                NavigationStack {
                    WorkoutSummaryView(viewModel: viewModel)
                }
            }
            .onChange(of: viewModel.sessionState) { _, state in
                session.sessionStateChanged(to: state, modelContext: modelContext)
            }
            .alert(
                "Save failed",
                isPresented: Binding(
                    get: { viewModel.saveErrorMessage != nil },
                    set: {
                        if !$0 {
                            viewModel.saveErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.saveErrorMessage ?? "")
            }
    }
}

extension View {
    /// Presents the shared workout session's screens. Attach once, at the shell.
    func workoutSessionHost() -> some View {
        modifier(WorkoutSessionHost())
    }
}
