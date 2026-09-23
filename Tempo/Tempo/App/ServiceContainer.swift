//
// ServiceContainer.swift
// Tempo
//
// Created by Tempo on 3/25/26.
//
//

import Foundation
import SwiftData

@Observable
@MainActor
final class ServiceContainer {
    /// Shared HTTP client for all backend calls (auth, sync, nutrition AI proxy,
    /// insights, etc.). Per INTELLIGENCE_REMEDIATION_PLAN.md §3 — all Claude
    /// calls flow through this client to the Vapor backend; iOS no longer
    /// embeds the Anthropic key.
    let apiClient: APIClient
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
    var receipts: (any ReceiptServiceProtocol)?
    var recipes: (any RecipeServiceProtocol)?
    var groceryList: (any GroceryListServiceProtocol)?
    let nutritionIntelligence: NutritionIntelligenceService
    /// Long-lived owner of the recovery AI insight generation. MUST be a single
    /// shared instance (not per-view) so its per-day single-flight dedup
    /// survives view remounts — otherwise rapid `.task` re-fires each spawn a
    /// fresh paid Haiku call (the retry-storm bug).
    let recoveryInsight: RecoveryAIInsightService
    /// §21 — phone side of the WCSession pair. Singleton (WCSession.default
    /// allows exactly one delegate); activated here so watch quick actions
    /// queued while the app was closed are delivered at launch.
    let watchConnectivity = PhoneWatchConnectivityService.shared
    /// §22 — the one app-level handler for every watch quick action other
    /// than `.logSet` (still owned by Training — see `setLogSetHandler`).
    /// Needs a ModelContext before it can act; wired via `configure(modelContext:)`
    /// from `TempoApp.init` once the ModelContainer exists.
    let watchActionRouter: WatchActionRouter
    let appState: AppState

    init(
        apiClient: APIClient,
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
        self.apiClient = apiClient
        self.authService = authService
        // AuthService is created without an APIClient (to break the
        // init cycle); wire it here so sign-in/refresh can reach the
        // backend. Without this, completeAppleSignIn throws
        // AuthError.notConfigured and Apple sign-in silently fails.
        authService.configure(apiClient: apiClient)
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
        self.nutritionIntelligence = NutritionIntelligenceService()
        self.recoveryInsight = RecoveryAIInsightService(apiClient: apiClient)
        let router = WatchActionRouter(
            accountabilityEngine: accountabilityEngine,
            notifications: notifications
        )
        watchActionRouter = router
        appState = AppState(authService: authService)
        watchConnectivity.activate()
        // §22 — single registrant PhoneWatchConnectivityService ever sees.
        // Training layers `.logSet` on top via `router.setLogSetHandler`
        // (TodayWorkoutView.task) once it loads.
        watchConnectivity.setQuickActionHandler { action in
            router.handle(action)
        }
    }

    /// Called once at launch (`TempoApp.init`) once the ModelContainer
    /// exists, so `watchActionRouter` can act on real SwiftData rows.
    func configure(modelContext: ModelContext) {
        watchActionRouter.configure(modelContext: modelContext)
    }

    static func mock() -> ServiceContainer {
        let auth = AuthService()
        let api = APIClient()
        return ServiceContainer(
            apiClient: api,
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
            pushRegistration: PushRegistrationService(apiClient: api),
            subscriptions: MockSubscriptionService(),
            nutrition: MockNutritionService()
        )
    }

    static func live() -> ServiceContainer {
        // Build the auth chain first so the APIClient is created WITH an
        // interceptor. APIClient.authInterceptor is a `let` (set only at
        // init); without this wiring no Bearer token is ever attached and
        // every protected endpoint 401s ("Missing Authorization header.").
        let auth = AuthService()
        let tokenProvider = AuthServiceTokenProvider(authService: auth)
        let interceptor = AuthInterceptor(tokenProvider: tokenProvider)
        let apiClient = APIClient(authInterceptor: interceptor)
        let healthKit = HealthKitService()
        return ServiceContainer(
            apiClient: apiClient,
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
            nutrition: NutritionService.live(healthKit: healthKit, apiClient: apiClient)
        )
    }
}
