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

    @State
    private var focusModel: AccountabilityViewModel?

    func body(content: Content) -> some View {
        let appState = services.appState
        content
            .onOpenURL { url in
                TempoDeepLink(url: url)?.apply(to: appState)
            }
            // `initial` covers a cold launch where the intent set the request
            // before this view appeared.
            .onChange(of: appState.requestedStart, initial: true) { _, request in
                if let request, appState.isOnboardingComplete {
                    handle(request, appState: appState)
                }
            }
            // Glasses the widget's button queued while the app was closed.
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    drainQueuedWater()
                }
            }
            .fullScreenCover(isPresented: Binding(
                get: { focusModel != nil },
                set: {
                    if !$0 {
                        focusModel = nil
                    }
                }
            )) {
                if let focusModel {
                    FocusTimerView(viewModel: focusModel)
                        .environment(\.tideMood, TideMood(score: appState.dayScore))
                        .preferredColorScheme(.dark)
                }
            }
    }

    private func drainQueuedWater() {
        let store = WaterStore(context: modelContext, healthKit: services.healthKit)
        WaterLogging.drainPending(store: store, context: modelContext)
    }

    private func handle(_ request: StartRequest, appState: AppState) {
        appState.requestedStart = nil
        // A "+" sheet left open would sit on top of what was asked for.
        appState.captureRequested = false
        switch request {
        case .workout:
            Task {
                let result = await services.workoutSession.start(modelContext: modelContext)
                if result == .notStartable {
                    // Nothing startable today: the Train tab says why.
                    appState.open(.train)
                }
            }
        case let .focus(minutes):
            guard focusModel == nil else {
                return
            }
            let model = AccountabilityViewModel(engine: services.accountabilityEngine)
            model.loadToday(modelContext: modelContext)
            if let minutes {
                model.configureFocusTimer(duration: TimeInterval(minutes * 60))
            }
            model.startFocusSession(modelContext: modelContext)
            focusModel = model
        }
    }
}

extension View {
    /// Acts on system start requests and `tempo://` links. Put it above
    /// `.environment(services)`'s children and below the model container.
    func tempoSystemRequests() -> some View {
        modifier(TempoSystemRequestHost())
    }
}
