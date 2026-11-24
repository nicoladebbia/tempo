//
// RecoveryCoachHooks.swift
// Tempo
//
// One modifier for ContentView: owns the Recovery Coach model, refreshes it when
// the app comes to the foreground or a push asks for a session, and keeps the
// pre-match reminder in step with the schedule. The model is shared through the
// environment: the one Fuel coach page (NutritionCoachView) shows it at the top.
// Kept out of ContentView so that file only gains one line.
//

import SwiftData
import SwiftUI

// MARK: - RecoveryCoachHooks

private struct RecoveryCoachHooks: ViewModifier {
    @Bindable var appState: AppState
    let services: ServiceContainer
    let modelContext: ModelContext

    @Environment(\.scenePhase) private var scenePhase
    @State private var model: RecoveryCoachModel?
    /// The launch `.task` already refreshes; the cold-launch `.active` must not fetch again.
    @State private var coldLaunch = ColdLaunchActivation()

    func body(content: Content) -> some View {
        content
            .environment(model)
            .task {
                let made = makeModel()
                model = made
                let requested = takeRequestedSessionID()
                await made.refresh(requestedID: requested)
                rescheduleReminder()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else {
                    return
                }
                let isColdLaunch = coldLaunch.isColdLaunch()
                guard let model, !isColdLaunch else {
                    return
                }
                let requested = takeRequestedSessionID()
                Task { await model.refresh(requestedID: requested) }
                rescheduleReminder()
            }
            // A push tap: pull the session list now (it may be a brand-new session). The
            // push itself opens Fuel > Coach (see NotificationRouter.coach), where the
            // session shows at the top of the one coach page.
            .onChange(of: appState.requestedCoach) { _, request in
                guard request != nil, let model else {
                    return
                }
                let requested = takeRequestedSessionID()
                Task { await model.refresh(requestedID: requested) }
            }
            // The phone just shared WHOOP access: a fetch that found none can now succeed.
            .onReceive(NotificationCenter.default.publisher(for: .tempoWhoopAccessShared).receive(on: DispatchQueue.main)) { _ in
                guard let model else {
                    return
                }
                Task { await model.whoopAccessShared() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .tempoCoachAnswerStored)) { _ in
                guard let model, model.hasSession else {
                    return
                }
                Task { await model.recompute() }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .tempoCoachSettingsChanged)
                    .merge(with: NotificationCenter.default.publisher(for: .tempoTrainingSettingsChanged))
                    .merge(with: NotificationCenter.default.publisher(for: .tempoWeeklyPlanApplied))
                    .debounce(for: .seconds(0.8), scheduler: DispatchQueue.main)
            ) { _ in
                rescheduleReminder()
            }
    }

    /// The session a push asked for, read once and cleared: the request is spent as soon as
    /// the model has been told, so the next tap on the same push asks again.
    private func takeRequestedSessionID() -> String? {
        let id = appState.requestedCoach?.id
        if id != nil {
            appState.requestedCoach = nil
        }
        return id
    }

    private func makeModel() -> RecoveryCoachModel {
        let context = modelContext
        return RecoveryCoachModel(
            api: LiveRecoveryCoachAPI(apiClient: services.apiClient),
            healthKit: services.healthKit,
            waterMl: { from, to in WaterStore.total(from: from, to: to, in: context) },
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
