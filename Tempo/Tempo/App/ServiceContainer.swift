//
// ServiceContainer.swift
// Tempo
//
// Created by Tempo on 25/03/2026.
//
//

import Foundation

@Observable
@MainActor
final class ServiceContainer {
    let authService: AuthService
    let healthKit: any HealthKitServiceProtocol
    let whoop: any WhoopServiceProtocol
    let calendar: any CalendarServiceProtocol
    let notifications: any NotificationServiceProtocol
    let trainingEngine: any TrainingEngineProtocol
    let recoveryEngine: any RecoveryEngineProtocol
    let scoringEngine: any ScoringEngineProtocol
    let xpEngine: any XPEngineProtocol
    let accountabilityEngine: AccountabilityEngine
    let syncCoordinator: any SyncCoordinatorProtocol
    let backgroundSync: BackgroundSyncService
    let networkMonitor: NetworkMonitor
    let pushRegistration: PushRegistrationService
    let subscriptions: any SubscriptionServiceProtocol
    let nutrition: any NutritionServiceProtocol
    /// Set by the View layer after the SwiftData ModelContext is available.
    /// Read by pantry-aware ViewModels (NutritionTabViewModel etc).
    var pantry: (any PantryServiceProtocol)?
    let appState: AppState

    init(
        authService: AuthService,
        healthKit: any HealthKitServiceProtocol,
        whoop: any WhoopServiceProtocol,
        calendar: any CalendarServiceProtocol,
        notifications: any NotificationServiceProtocol,
        trainingEngine: any TrainingEngineProtocol,
        recoveryEngine: any RecoveryEngineProtocol,
        scoringEngine: any ScoringEngineProtocol,
        xpEngine: any XPEngineProtocol,
        accountabilityEngine: AccountabilityEngine,
        syncCoordinator: any SyncCoordinatorProtocol,
        backgroundSync: BackgroundSyncService,
        networkMonitor: NetworkMonitor,
        pushRegistration: PushRegistrationService,
        subscriptions: any SubscriptionServiceProtocol,
        nutrition: any NutritionServiceProtocol
    ) {
        self.authService = authService
        self.healthKit = healthKit
        self.whoop = whoop
        self.calendar = calendar
        self.notifications = notifications
        self.trainingEngine = trainingEngine
        self.recoveryEngine = recoveryEngine
        self.scoringEngine = scoringEngine
        self.xpEngine = xpEngine
        self.accountabilityEngine = accountabilityEngine
        self.syncCoordinator = syncCoordinator
        self.backgroundSync = backgroundSync
        self.networkMonitor = networkMonitor
        self.pushRegistration = pushRegistration
        self.subscriptions = subscriptions
        self.nutrition = nutrition
        appState = AppState(authService: authService)
    }

    static func mock() -> ServiceContainer {
        let auth = AuthService()
        return ServiceContainer(
            authService: auth,
            healthKit: MockHealthKitService(),
            whoop: MockWhoopService(),
            calendar: MockCalendarService(),
            notifications: MockNotificationService(),
            trainingEngine: MockTrainingEngine(),
            recoveryEngine: MockRecoveryEngine(),
            scoringEngine: MockScoringEngine(),
            xpEngine: MockXPEngine(),
            accountabilityEngine: AccountabilityEngine(),
            syncCoordinator: MockSyncCoordinator(),
            backgroundSync: BackgroundSyncService(),
            networkMonitor: NetworkMonitor(),
            pushRegistration: PushRegistrationService(apiClient: APIClient()),
            subscriptions: MockSubscriptionService(),
            nutrition: MockNutritionService()
        )
    }

    static func live(apiClient: APIClient) -> ServiceContainer {
        let auth = AuthService()
        let healthKit = HealthKitService()
        return ServiceContainer(
            authService: auth,
            healthKit: healthKit,
            whoop: WhoopService(),
            calendar: CalendarService(),
            notifications: NotificationService(),
            trainingEngine: TrainingEngine(),
            recoveryEngine: RecoveryEngine(),
            scoringEngine: ScoringEngine(),
            xpEngine: XPEngine(),
            accountabilityEngine: AccountabilityEngine(),
            syncCoordinator: MockSyncCoordinator(),
            backgroundSync: BackgroundSyncService(),
            networkMonitor: NetworkMonitor(),
            pushRegistration: PushRegistrationService(apiClient: apiClient),
            subscriptions: SubscriptionService(),
            nutrition: NutritionService.live(healthKit: healthKit)
        )
    }
}
