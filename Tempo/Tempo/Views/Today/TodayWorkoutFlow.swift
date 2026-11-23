//
// TodayWorkoutFlow.swift
// Tempo
//
// Starts today's session straight from Today and hosts its screens. Same
// view model and cover wiring as TrainingTabView and the Move detail, so a
// session behaves identically wherever it was started.
//

import SwiftData
import SwiftUI

struct TodayWorkoutFlow: ViewModifier {
    /// Bump to start (or resume) today's session.
    let startRequest: Int

    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext

    @State
    private var trainingVM: TrainingViewModel?
    @State
    private var showActiveWorkout = false
    @State
    private var showSummary = false
    @State
    private var started = 0

    func body(content: Content) -> some View {
        content
            .onChange(of: startRequest) {
                start()
            }
            .sensoryFeedback(.success, trigger: started)
            .fullScreenCover(isPresented: $showActiveWorkout) {
                if let trainingVM {
                    NavigationStack {
                        ActiveWorkoutView(viewModel: trainingVM)
                    }
                }
            }
            .fullScreenCover(isPresented: $showSummary, onDismiss: {
                showSummary = false
                // However the summary closed, its feedback is now final.
                trainingVM?.applyPendingLearning(modelContext: modelContext, summaryClosed: true)
            }) {
                if let trainingVM {
                    NavigationStack {
                        WorkoutSummaryView(viewModel: trainingVM)
                    }
                }
            }
            .onChange(of: trainingVM?.sessionState) { _, newState in
                if newState?.needsWorkoutScreen == true, !showActiveWorkout {
                    showActiveWorkout = true
                } else if case .summary = newState {
                    // Save the moment the session reaches its summary, so
                    // swiping the summary away never loses the workout.
                    trainingVM?.persistCompletion(modelContext: modelContext)
                    showActiveWorkout = false
                    showSummary = true
                } else if case .discarded = newState {
                    showActiveWorkout = false
                    showSummary = false
                    if let trainingVM {
                        Task { @MainActor in
                            await trainingVM.loadToday(modelContext: modelContext)
                            trainingVM.sessionState = .idle
                        }
                    }
                }
            }
            .alert(
                "Save failed",
                isPresented: Binding(
                    get: { trainingVM?.saveErrorMessage != nil },
                    set: {
                        if !$0 {
                            trainingVM?.saveErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(trainingVM?.saveErrorMessage ?? "")
            }
    }

    private func start() {
        Task { @MainActor in
            let vm = trainingVM ?? TrainingViewModel(
                trainingEngine: services.trainingEngine,
                whoop: services.whoop,
                healthKit: services.healthKit,
                apiClient: services.apiClient,
                calendarService: services.calendar
            )
            trainingVM = vm
            await vm.loadToday(modelContext: modelContext)
            guard vm.startWorkout() else {
                // Nothing startable here (plan changed under us): the Train
                // tab shows why and what to do instead.
                services.appState.activeTab = .train
                return
            }
            showActiveWorkout = true
            started += 1
        }
    }
}

extension View {
    func todayWorkoutFlow(startRequest: Int) -> some View {
        modifier(TodayWorkoutFlow(startRequest: startRequest))
    }
}
