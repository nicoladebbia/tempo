//
// RecoveryCoachHooks.swift
// Tempo
//
// One modifier for ContentView: owns the Recovery Coach model, refreshes it when
// the app comes to the foreground, presents the coach screen when a push (or the
// Today card) asks for it, and keeps the pre-match reminder in step with the
// schedule. Kept out of ContentView so that file only gains one line.
//

import SwiftData
import SwiftUI

private struct RecoveryCoachHooks: ViewModifier {
    @Bindable var appState: AppState
    let services: ServiceContainer
    let modelContext: ModelContext

    @Environment(\.scenePhase) private var scenePhase
    @State private var model: RecoveryCoachModel?

    func body(content: Content) -> some View {
        content
            .environment(model)
            .task {
                let made = makeModel()
                model = made
                await made.refresh(requestedID: appState.requestedCoach?.id)
                rescheduleReminder()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, let model else { return }
                Task { await model.refresh(requestedID: appState.requestedCoach?.id) }
                rescheduleReminder()
            }
            // A push tap: pull the session list now (it may be a brand-new session).
            .onChange(of: appState.requestedCoach) { _, request in
                guard let request, let model else { return }
                Task { await model.refresh(requestedID: request.id) }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .tempoCoachSettingsChanged)
                    .merge(with: NotificationCenter.default.publisher(for: .tempoTrainingSettingsChanged))
                    .merge(with: NotificationCenter.default.publisher(for: .tempoWeeklyPlanApplied))
                    .debounce(for: .seconds(0.8), scheduler: DispatchQueue.main)
            ) { _ in
                rescheduleReminder()
            }
            .sheet(item: $appState.requestedCoach) { _ in
                if let model {
                    RecoveryCoachView(model: model) { appState.requestedCoach = nil }
                }
            }
    }

    private func makeModel() -> RecoveryCoachModel {
        let context = modelContext
        return RecoveryCoachModel(
            api: LiveRecoveryCoachAPI(apiClient: services.apiClient),
            healthKit: services.healthKit,
            waterMl: { from, to in
                let descriptor = FetchDescriptor<WaterIntakeLog>(
                    predicate: #Predicate<WaterIntakeLog> { $0.loggedAt >= from && $0.loggedAt <= to }
                )
                return ((try? context.fetch(descriptor)) ?? []).reduce(0) { $0 + $1.ml }
            },
            location: CoreLocationFixProvider()
        )
    }

    private func rescheduleReminder() {
        PreMatchWeighInScheduler.reschedule(modelContext: modelContext, healthKit: services.healthKit)
    }
}

extension View {
    /// Recovery Coach: model, foreground refresh, push-to-screen and the pre-match reminder.
    func recoveryCoachHooks(appState: AppState, services: ServiceContainer, modelContext: ModelContext) -> some View {
        modifier(RecoveryCoachHooks(appState: appState, services: services, modelContext: modelContext))
    }
}
