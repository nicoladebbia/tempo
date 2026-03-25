import Foundation

@Observable
@MainActor
final class ServiceContainer {

    let authService: AuthService
    let healthKit: any HealthKitServiceProtocol
    let whoop: any WhoopServiceProtocol
    let nutriTrack: any NutriTrackServiceProtocol
    let calendar: any CalendarServiceProtocol
    let notifications: any NotificationServiceProtocol
    let trainingEngine: any TrainingEngineProtocol
    let recoveryEngine: any RecoveryEngineProtocol
    let scoringEngine: any ScoringEngineProtocol
    let xpEngine: any XPEngineProtocol
    let syncCoordinator: any SyncCoordinatorProtocol
    let backgroundSync: BackgroundSyncService
    let networkMonitor: NetworkMonitor
    let pushRegistration: PushRegistrationService
    let subscriptions: any SubscriptionServiceProtocol
    let appState: AppState

    init(
        authService: AuthService,
        healthKit: any HealthKitServiceProtocol,
        whoop: any WhoopServiceProtocol,
        nutriTrack: any NutriTrackServiceProtocol,
        calendar: any CalendarServiceProtocol,
        notifications: any NotificationServiceProtocol,
        trainingEngine: any TrainingEngineProtocol,
        recoveryEngine: any RecoveryEngineProtocol,
        scoringEngine: any ScoringEngineProtocol,
        xpEngine: any XPEngineProtocol,
        syncCoordinator: any SyncCoordinatorProtocol,
        backgroundSync: BackgroundSyncService,
        networkMonitor: NetworkMonitor,
        pushRegistration: PushRegistrationService,
        subscriptions: any SubscriptionServiceProtocol
    ) {
        self.authService = authService
        self.healthKit = healthKit
        self.whoop = whoop
        self.nutriTrack = nutriTrack
        self.calendar = calendar
        self.notifications = notifications
        self.trainingEngine = trainingEngine
        self.recoveryEngine = recoveryEngine
        self.scoringEngine = scoringEngine
        self.xpEngine = xpEngine
        self.syncCoordinator = syncCoordinator
        self.backgroundSync = backgroundSync
        self.networkMonitor = networkMonitor
        self.pushRegistration = pushRegistration
        self.subscriptions = subscriptions
        self.appState = AppState(authService: authService)
    }

    static func mock() -> ServiceContainer {
        let auth = AuthService()
        return ServiceContainer(
            authService: auth,
            healthKit: MockHealthKitService(),
            whoop: MockWhoopService(),
            nutriTrack: MockNutriTrackService(),
            calendar: MockCalendarService(),
            notifications: MockNotificationService(),
            trainingEngine: MockTrainingEngine(),
            recoveryEngine: MockRecoveryEngine(),
            scoringEngine: MockScoringEngine(),
            xpEngine: MockXPEngine(),
            syncCoordinator: MockSyncCoordinator(),
            backgroundSync: BackgroundSyncService(),
            networkMonitor: NetworkMonitor(),
            pushRegistration: PushRegistrationService(apiClient: APIClient()),
            subscriptions: MockSubscriptionService()
        )
    }

    static func live(apiClient: APIClient) -> ServiceContainer {
        let auth = AuthService()
        return ServiceContainer(
            authService: auth,
            healthKit: HealthKitService(),
            whoop: WhoopService(apiClient: apiClient),
            nutriTrack: NutriTrackService(apiClient: apiClient),
            calendar: CalendarService(),
            notifications: NotificationService(),
            trainingEngine: TrainingEngine(),
            recoveryEngine: RecoveryEngine(),
            scoringEngine: MockScoringEngine(),
            xpEngine: MockXPEngine(),
            syncCoordinator: MockSyncCoordinator(),
            backgroundSync: BackgroundSyncService(),
            networkMonitor: NetworkMonitor(),
            pushRegistration: PushRegistrationService(apiClient: apiClient),
            subscriptions: SubscriptionService()
        )
    }
}
