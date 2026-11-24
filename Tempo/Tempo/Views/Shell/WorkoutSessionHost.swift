//
// WorkoutSessionHost.swift
// Tempo
//
// The workout screens, hosted once for the whole app. Today, the Train tab
// and the Move detail all start the shared session
// (`WorkoutSessionCoordinator`); this is the only place that presents it.
//
// The logger grows out of the button that started it. A Start button opts in
// with `.workoutZoomSource(<its tab>)`; the host zooms from the source that
// belongs to the tab on screen, and falls back to the plain cover when the
// button did not opt in.
//

import SwiftData
import SwiftUI

extension EnvironmentValues {
    /// The namespace the workout logger zooms out of. Set by the host.
    @Entry var workoutZoomNamespace: Namespace.ID?
}

/// Marks the view the workout logger opens out of.
private struct WorkoutZoomSource: ViewModifier {
    let tab: AppTab
    @Environment(\.workoutZoomNamespace)
    private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: tab, in: namespace)
        } else {
            content
        }
    }
}

struct WorkoutSessionHost: ViewModifier {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext
    @Namespace
    private var zoom

    func body(content: Content) -> some View {
        @Bindable
        var session = services.workoutSession
        let viewModel = session.viewModel
        return content
            .environment(\.workoutZoomNamespace, zoom)
            .tideCovered(session.showActiveWorkout || session.showSummary)
            .sensoryFeedback(.success, trigger: session.starts)
            .fullScreenCover(isPresented: $session.showActiveWorkout) {
                NavigationStack {
                    ActiveWorkoutView(viewModel: viewModel)
                }
                .navigationTransition(.zoom(sourceID: services.appState.activeTab, in: zoom))
                // The zoom adds a pull-down to close; a set in progress is not
                // something to lose by brushing the screen.
                .interactiveDismissDisabled()
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
    /// Marks this view (a Start button) as the place the workout logger zooms
    /// out of when the session starts from `tab`.
    func workoutZoomSource(_ tab: AppTab) -> some View {
        modifier(WorkoutZoomSource(tab: tab))
    }

    /// Presents the shared workout session's screens. Attach once, at the shell.
    func workoutSessionHost() -> some View {
        modifier(WorkoutSessionHost())
    }
}
