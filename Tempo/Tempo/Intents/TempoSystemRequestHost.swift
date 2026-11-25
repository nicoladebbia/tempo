//
// TempoSystemRequestHost.swift
// Tempo
//
// The one place that acts on what the system asks the app to start: the
// "Start workout" and "Start focus" intents (`AppState.requestedStart`) and
// the `tempo://` links a widget opens. It sits at the very top of the app, so
// it works whichever screen is up, and it starts things the way the Today
// buttons do: the workout through the app's one `WorkoutSessionCoordinator`
// (its screen is hosted by the shell), the focus timer full screen.
//
// Two full-screen covers cannot be up at once, so a workout request first
// puts a focus timer away (the timer keeps running), and a focus request is
// not started while the workout screen is up.
//

import SwiftData
import SwiftUI

// MARK: - TempoSystemRequestHost

struct TempoSystemRequestHost: ViewModifier {
    @Environment(ServiceContainer.self)
    private var services
    @Environment(\.modelContext)
    private var modelContext

    @Environment(\.scenePhase)
    private var scenePhase

    /// The timer this host started. Kept while it runs, even with its screen put away.
    @State
    private var focusModel: AccountabilityViewModel?
    @State
    private var showFocus = false

    func body(content: Content) -> some View {
        let appState = services.appState
        content
            .onOpenURL { url in
                TempoDeepLink(url: url)?.apply(to: appState)
            }
            // `initial` covers a cold launch where the intent set the request
            // before this view appeared.
            .onChange(of: appState.requestedStart, initial: true) { _, _ in
                handlePendingRequest()
            }
            .onChange(of: appState.isOnboardingComplete) { _, _ in
                handlePendingRequest()
            }
            // Glasses the widget's button queued while the app was closed.
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    drainQueuedWater()
                }
            }
            .fullScreenCover(isPresented: $showFocus, onDismiss: releaseFinishedTimer) {
                if let focusModel {
                    FocusTimerView(viewModel: focusModel)
                        .environment(\.tideMood, TideMood(score: appState.dayScore))
                        .preferredColorScheme(.dark)
                }
            }
    }

    // MARK: Water

    private func drainQueuedWater() {
        let store = WaterStore(context: modelContext, healthKit: services.healthKit)
        WaterLogging.drainPending(store: store, context: modelContext)
    }

    // MARK: Requests

    private func handlePendingRequest() {
        let appState = services.appState
        guard let request = appState.requestedStart, appState.isOnboardingComplete else {
            return
        }
        appState.requestedStart = nil
        // A "+" sheet left open would sit on top of what was asked for.
        appState.captureRequested = false
        switch request {
        case .workout: startWorkout(appState: appState)
        case let .focus(minutes): startFocus(minutes: minutes)
        }
    }

    private func startWorkout(appState: AppState) {
        Task {
            if showFocus {
                // The shell presents the workout screen; wait for the timer's to go.
                showFocus = false
                try? await Task.sleep(for: Tide.sheetHandoff)
            }
            let result = await services.workoutSession.start(modelContext: modelContext)
            if result == .notStartable {
                // Nothing startable today: the Train tab says why.
                appState.open(.train)
            }
        }
    }

    private func startFocus(minutes: Int?) {
        let session = services.workoutSession
        guard !session.showActiveWorkout, !session.showSummary else {
            return
        }
        // A timer already running is shown again, never doubled.
        if let focusModel, Self.isRunning(focusModel) {
            showFocus = true
            return
        }
        // One started from a Today, Mind or Lockdown button lives in that
        // screen's own model: do not start a second one next to it.
        if LiveActivityCoordinator.shared.hasLiveSession(.focusTimer) {
            services.appState.open(.today)
            return
        }
        let model = AccountabilityViewModel(engine: services.accountabilityEngine)
        model.loadToday(modelContext: modelContext)
        if let minutes {
            model.configureFocusTimer(duration: TimeInterval(minutes * 60))
        }
        model.startFocusSession(modelContext: modelContext)
        focusModel = model
        showFocus = true
    }

    /// The timer's screen went away: forget a timer that is over, keep one that runs.
    private func releaseFinishedTimer() {
        if let focusModel, !Self.isRunning(focusModel) {
            self.focusModel = nil
        }
    }

    private static func isRunning(_ model: AccountabilityViewModel) -> Bool {
        if case .paused = model.focusState {
            return true
        }
        return model.focusState.isActive
    }
}

extension View {
    /// Acts on system start requests and `tempo://` links. Put it above
    /// `.environment(services)`'s children and below the model container.
    func tempoSystemRequests() -> some View {
        modifier(TempoSystemRequestHost())
    }
}
