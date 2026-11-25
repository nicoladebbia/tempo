//
// WorkoutSessionCoordinator.swift
// Tempo
//
// The one owner of the training session. Today, the Train tab and the Move
// detail all use the view model held here, so a session started on one of
// them is the same session on the others, and there is one set of workout
// screens (hosted once by the shell, see `WorkoutSessionHost`).
//

import SwiftData
import SwiftUI

@Observable
@MainActor
final class WorkoutSessionCoordinator {
    enum StartResult: Equatable {
        /// A new session began and its screen is up.
        case started
        /// A session was already live (or waiting to be resumed): its screen is up.
        case alreadyRunning
        /// Another start is still being worked out; this tap was dropped.
        case busy
        /// Today has nothing to start (finished, skipped, no plan).
        case notStartable
    }

    let viewModel: TrainingViewModel
    var showActiveWorkout = false
    var showSummary = false
    /// Counts sessions started here; drives the start haptic.
    private(set) var starts = 0
    private(set) var isStarting = false
    /// True once today's plan (and the daily coach) has been resolved this launch.
    private(set) var hasLoadedToday = false

    private var planLoad: Task<Void, Never>?

    init(viewModel: TrainingViewModel) {
        self.viewModel = viewModel
    }

    /// Resolves today's plan once per launch. Safe to call from every screen:
    /// later calls get the same task back.
    @discardableResult
    func prepare(modelContext: ModelContext) -> Task<Void, Never> {
        if let planLoad {
            return planLoad
        }
        let task = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await viewModel.loadToday(modelContext: modelContext)
            hasLoadedToday = true
        }
        planLoad = task
        return task
    }

    /// Starts (or resumes) today's session and puts its screen up. Taps that
    /// arrive while a start is in progress, or while a session is already on
    /// screen, never start a second one.
    func start(modelContext: ModelContext) async -> StartResult {
        guard !isStarting else {
            return .busy
        }
        if viewModel.sessionState.isActive {
            showActiveWorkout = true
            return .alreadyRunning
        }
        isStarting = true
        defer { isStarting = false }

        // `loadToday` drops a call made while another is running, so wait for
        // the launch load rather than racing it with a plan that is not there yet.
        if let planLoad, !hasLoadedToday {
            await planLoad.value
        } else {
            await viewModel.loadToday(modelContext: modelContext)
        }
        if viewModel.sessionState.isActive {
            // Adopted on load (started on the watch): show it, don't restart it.
            showActiveWorkout = true
            return .alreadyRunning
        }
        guard viewModel.startWorkout() else {
            return .notStartable
        }
        showActiveWorkout = true
        starts += 1
        return .started
    }

    /// Keeps the workout screens in step with the session. Called by the one
    /// host whenever the session state changes.
    func sessionStateChanged(to state: WorkoutSessionState, modelContext: ModelContext) {
        if state.needsWorkoutScreen {
            // A session that went live without a Start button (started on the
            // watch and adopted on load, or crash recovery) still needs its screen.
            if !showActiveWorkout {
                showActiveWorkout = true
            }
        } else if case .summary = state {
            // Save the moment the session reaches its summary, so swiping the
            // summary away never loses the workout. Idempotent.
            viewModel.persistCompletion(modelContext: modelContext)
            showActiveWorkout = false
            showSummary = true
        } else if case .discarded = state {
            // Close the screens and reload today so the day is restartable.
            showActiveWorkout = false
            showSummary = false
            Task { @MainActor [viewModel] in
                await viewModel.loadToday(modelContext: modelContext)
                viewModel.sessionState = .idle
            }
        }
    }
}
