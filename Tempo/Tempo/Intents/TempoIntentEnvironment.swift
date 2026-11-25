//
// TempoIntentEnvironment.swift
// Tempo
//
// What an App Intent needs from the running app: the one SwiftData context
// every screen uses, Apple Health, and the app's routing state. The app sets
// these up once in `TempoApp.init`; an intent that wakes the app in the
// background waits for that to finish. Tests set `override` with an in-memory
// store, so the same `perform` code runs against fakes.
//

import Foundation
import SwiftData

@MainActor
struct TempoIntentEnvironment {
    let context: ModelContext
    let healthKit: (any HealthKitServiceProtocol)?
    let appState: AppState?
    /// Where the widgets' numbers are written. Tests give it their own suite.
    var widgetDefaults: UserDefaults? = UserDefaults(suiteName: WidgetSnapshot.appGroupID)

    /// Tests inject a store here; production leaves it nil.
    static var override: TempoIntentEnvironment?

    /// The running app's environment. Waits a few seconds for a cold start
    /// (the system launches the app in the background to run an intent);
    /// nil when the app never finished starting.
    static func resolve(timeout: Duration = .seconds(5)) async -> TempoIntentEnvironment? {
        if let override {
            return override
        }
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let container = TempoNotificationDelegate.modelContainer,
               let services = TempoNotificationDelegate.services
            {
                return TempoIntentEnvironment(
                    context: container.mainContext,
                    healthKit: services.healthKit,
                    appState: services.appState
                )
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }
}
