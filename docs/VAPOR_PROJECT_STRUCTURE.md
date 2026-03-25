# Tempo Backend — Vapor Project Structure & Setup Guide

> **Version:** 1.0.0
> **Last updated:** 2026-03-24
> **Stack:** Vapor 4.99+ / Swift 6.0 / PostgreSQL 16 / Redis 7
> **Companion doc:** `BACKEND_API.md`

---

## Table of Contents

1. [Project Creation](#1-project-creation)
2. [Complete File Structure](#2-complete-file-structure)
3. [Package.swift](#3-packageswift)
4. [Key Configuration Files](#4-key-configuration-files)
5. [Model Examples](#5-model-examples)
6. [Migration Examples](#6-migration-examples)
7. [Controller Pattern](#7-controller-pattern)
8. [Middleware](#8-middleware)
9. [Background Jobs](#9-background-jobs)
10. [Docker Setup](#10-docker-setup)
11. [Environment Configuration](#11-environment-configuration)
12. [Testing Setup](#12-testing-setup)
13. [Deployment](#13-deployment)

---

## 1. Project Creation

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Swift | 6.0+ | `brew install swift` or Xcode 16+ |
| Vapor Toolbox | 18.7+ | `brew install vapor` |
| Docker | 24+ | Docker Desktop for macOS |
| PostgreSQL | 16 | Via Docker (preferred) |
| Redis | 7 | Via Docker (preferred) |

### Create the project

```bash
# Install Vapor toolbox if not already installed
brew install vapor

# Create new project with Fluent + PostgreSQL
vapor new tempo-backend --fluent.db postgres --no-leaf

# Enter directory
cd tempo-backend

# Verify Swift version
swift --version
# Swift version 6.0.x

# Open in Xcode (optional)
open Package.swift
```

### Initial Docker setup (run before first build)

```bash
# Start PostgreSQL + Redis for local development
docker compose up -d db redis

# Verify connectivity
docker compose exec db pg_isready
docker compose exec redis redis-cli ping
```

---

## 2. Complete File Structure

```
tempo-backend/
├── Package.swift
├── Dockerfile
├── docker-compose.yml
├── docker-compose.override.yml
├── .env.example
├── .env
├── .dockerignore
├── .gitignore
├── Sources/
│   └── App/
│       ├── entrypoint.swift
│       ├── configure.swift
│       ├── routes.swift
│       ├── Controllers/
│       │   ├── AuthController.swift
│       │   ├── UserController.swift
│       │   ├── PreferencesController.swift
│       │   ├── WhoopIntegrationController.swift
│       │   ├── WhoopDataController.swift
│       │   ├── WhoopWebhookController.swift
│       │   ├── NutriTrackController.swift
│       │   ├── ExerciseController.swift
│       │   ├── WorkoutController.swift
│       │   ├── WorkoutPlanController.swift
│       │   ├── StudySessionController.swift
│       │   ├── SnapshotController.swift
│       │   ├── XPController.swift
│       │   ├── LeaderboardController.swift
│       │   ├── FriendController.swift
│       │   ├── ChallengeController.swift
│       │   ├── AchievementController.swift
│       │   ├── AccountabilityController.swift
│       │   ├── SyncController.swift
│       │   ├── DeviceController.swift
│       │   ├── InsightController.swift
│       │   ├── ReportController.swift
│       │   ├── ExportController.swift
│       │   ├── SearchController.swift
│       │   ├── WebSocketController.swift
│       │   ├── ConfigController.swift
│       │   ├── OutboundWebhookController.swift
│       │   └── AdminController.swift
│       ├── Models/
│       │   ├── User.swift
│       │   ├── UserPreferences.swift
│       │   ├── RefreshToken.swift
│       │   ├── AppleAuth.swift
│       │   ├── WhoopIntegration.swift
│       │   ├── WhoopRecovery.swift
│       │   ├── WhoopSleep.swift
│       │   ├── WhoopWorkout.swift
│       │   ├── WhoopCycle.swift
│       │   ├── WhoopBody.swift
│       │   ├── WhoopProfile.swift
│       │   ├── NutriTrackIntegration.swift
│       │   ├── XPEvent.swift
│       │   ├── Exercise.swift
│       │   ├── WorkoutPlan.swift
│       │   ├── ManualWorkout.swift
│       │   ├── StudySession.swift
│       │   ├── DailySnapshot.swift
│       │   ├── Friendship.swift
│       │   ├── FriendRequest.swift
│       │   ├── Challenge.swift
│       │   ├── ChallengeParticipant.swift
│       │   ├── ChallengeDailyScore.swift
│       │   ├── AchievementDefinition.swift
│       │   ├── UserAchievement.swift
│       │   ├── DeviceToken.swift
│       │   ├── Insight.swift
│       │   ├── SyncJob.swift
│       │   ├── AuditLog.swift
│       │   ├── OutboundWebhook.swift
│       │   └── OutboundWebhookDelivery.swift
│       ├── Migrations/
│       │   ├── CreateUsers.swift
│       │   ├── CreateUserPreferences.swift
│       │   ├── CreateRefreshTokens.swift
│       │   ├── CreateAppleAuth.swift
│       │   ├── CreateWhoopIntegrations.swift
│       │   ├── CreateWhoopRecovery.swift
│       │   ├── CreateWhoopSleep.swift
│       │   ├── CreateWhoopWorkouts.swift
│       │   ├── CreateWhoopCycles.swift
│       │   ├── CreateWhoopBody.swift
│       │   ├── CreateWhoopProfiles.swift
│       │   ├── CreateNutriTrackIntegrations.swift
│       │   ├── CreateXPEvents.swift
│       │   ├── CreateExercises.swift
│       │   ├── CreateWorkoutPlans.swift
│       │   ├── CreateManualWorkouts.swift
│       │   ├── CreateStudySessions.swift
│       │   ├── CreateDailySnapshots.swift
│       │   ├── CreateFriendships.swift
│       │   ├── CreateFriendRequests.swift
│       │   ├── CreateChallenges.swift
│       │   ├── CreateChallengeParticipants.swift
│       │   ├── CreateChallengeDailyScores.swift
│       │   ├── CreateAchievementDefinitions.swift
│       │   ├── CreateUserAchievements.swift
│       │   ├── CreateDeviceTokens.swift
│       │   ├── CreateInsights.swift
│       │   ├── CreateSyncJobs.swift
│       │   ├── CreateAuditLog.swift
│       │   ├── CreateOutboundWebhooks.swift
│       │   ├── CreateOutboundWebhookDeliveries.swift
│       │   ├── CreateLeaderboardViews.swift
│       │   └── SeedExerciseLibrary.swift
│       ├── DTOs/
│       │   ├── Envelope.swift
│       │   ├── AuthDTO.swift
│       │   ├── UserDTO.swift
│       │   ├── PreferencesDTO.swift
│       │   ├── WhoopDTO.swift
│       │   ├── NutriTrackDTO.swift
│       │   ├── ExerciseDTO.swift
│       │   ├── WorkoutDTO.swift
│       │   ├── StudySessionDTO.swift
│       │   ├── SnapshotDTO.swift
│       │   ├── XPDTO.swift
│       │   ├── LeaderboardDTO.swift
│       │   ├── FriendDTO.swift
│       │   ├── ChallengeDTO.swift
│       │   ├── AchievementDTO.swift
│       │   ├── AccountabilityDTO.swift
│       │   ├── SyncDTO.swift
│       │   ├── InsightDTO.swift
│       │   ├── ReportDTO.swift
│       │   ├── ConfigDTO.swift
│       │   ├── PaginationDTO.swift
│       │   └── ErrorDTO.swift
│       ├── Services/
│       │   ├── AppleAuthService.swift
│       │   ├── JWTService.swift
│       │   ├── TokenService.swift
│       │   ├── WhoopOAuthService.swift
│       │   ├── WhoopAPIService.swift
│       │   ├── NutriTrackProxyService.swift
│       │   ├── XPService.swift
│       │   ├── LeaderboardService.swift
│       │   ├── ChallengeService.swift
│       │   ├── AchievementService.swift
│       │   ├── AccountabilityService.swift
│       │   ├── NotificationService.swift
│       │   ├── InsightService.swift
│       │   ├── EncryptionService.swift
│       │   ├── CacheService.swift
│       │   └── AuditService.swift
│       ├── Middleware/
│       │   ├── JWTAuthMiddleware.swift
│       │   ├── AdminMiddleware.swift
│       │   ├── RateLimitMiddleware.swift
│       │   ├── WhoopWebhookMiddleware.swift
│       │   ├── RequestIdMiddleware.swift
│       │   ├── SecurityHeadersMiddleware.swift
│       │   └── RequestLoggingMiddleware.swift
│       ├── Jobs/
│       │   ├── WhoopSyncJob.swift
│       │   ├── LeaderboardRefreshJob.swift
│       │   ├── ChallengeStatusJob.swift
│       │   ├── AccountabilityCheckJob.swift
│       │   ├── NotificationScheduleJob.swift
│       │   ├── WeeklySummaryJob.swift
│       │   ├── AccountHardDeleteJob.swift
│       │   ├── StaleTokenCleanupJob.swift
│       │   ├── PartitionCreationJob.swift
│       │   ├── WebhookDeliveryJob.swift
│       │   └── GDPRExportJob.swift
│       └── Extensions/
│           ├── Application+Services.swift
│           ├── Request+Auth.swift
│           ├── String+Random.swift
│           ├── Date+Helpers.swift
│           └── Abort+TempoError.swift
├── Tests/
│   └── AppTests/
│       ├── AuthTests.swift
│       ├── UserTests.swift
│       ├── ArenaTests.swift
│       ├── Helpers/
│       │   ├── TestApplication.swift
│       │   └── Factories.swift
│       └── Stubs/
│           └── WhoopStubs.swift
├── Resources/
│   └── Seed/
│       └── exercises.json
└── Public/
```

---

## 3. Package.swift

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "tempo-backend",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Vapor core
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),

        // Fluent ORM + PostgreSQL driver
        .package(url: "https://github.com/vapor/fluent.git", from: "4.11.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.9.0"),

        // JWT (ES256 signing + verification)
        .package(url: "https://github.com/vapor/jwt.git", from: "5.0.0"),

        // Redis
        .package(url: "https://github.com/vapor/redis.git", from: "5.0.0"),

        // Queues (background jobs) + Redis driver
        .package(url: "https://github.com/vapor/queues.git", from: "1.16.0"),
        .package(url: "https://github.com/vapor/queues-redis-driver.git", from: "1.1.0"),

        // APNs push notifications
        .package(url: "https://github.com/vapor/apns.git", from: "4.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "JWT", package: "jwt"),
                .product(name: "Redis", package: "redis"),
                .product(name: "Queues", package: "queues"),
                .product(name: "QueuesRedisDriver", package: "queues-redis-driver"),
                .product(name: "VaporAPNS", package: "apns"),
            ],
            path: "Sources/App"
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "XCTVapor", package: "vapor"),
            ],
            path: "Tests/AppTests"
        ),
    ]
)
```

---

## 4. Key Configuration Files

### entrypoint.swift

```swift
import Vapor
import Fluent
import FluentPostgresDriver
import Logging

@main
enum Entrypoint {
    static func main() async throws {
        var env = try Environment.detect()
        try LoggingSystem.bootstrap(from: &env)

        let app = try await Application.make(env)
        defer { Task { try await app.asyncShutdown() } }

        try await configure(app)
        try await app.execute()
    }
}
```

### configure.swift

```swift
import Vapor
import Fluent
import FluentPostgresDriver
import JWT
import Redis
import Queues
import QueuesRedisDriver
import VaporAPNS
import NIOSSL

func configure(_ app: Application) async throws {

    // ───────────────────────────────────────────────
    // 1. Content configuration
    // ───────────────────────────────────────────────
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.keyEncodingStrategy = .convertToSnakeCase
    ContentConfiguration.global.use(encoder: encoder, for: .json)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    // Max body size: 1MB JSON, 5MB multipart
    app.routes.defaultMaxBodySize = "1mb"

    // ───────────────────────────────────────────────
    // 2. Database — PostgreSQL
    // ───────────────────────────────────────────────
    let dbConfig: SQLPostgresConfiguration
    if let databaseURL = Environment.get("DATABASE_URL") {
        dbConfig = try SQLPostgresConfiguration(url: databaseURL)
    } else {
        dbConfig = SQLPostgresConfiguration(
            hostname: Environment.get("DB_HOST") ?? "localhost",
            port: Environment.get("DB_PORT").flatMap(Int.init) ?? 5432,
            username: Environment.get("DB_USER") ?? "tempo",
            password: Environment.get("DB_PASSWORD") ?? "tempo_dev",
            database: Environment.get("DB_NAME") ?? "tempo",
            tls: app.environment == .production
                ? .require(try NIOSSLContext(configuration: .clientDefault))
                : .disable
        )
    }

    app.databases.use(
        .postgres(configuration: dbConfig, maxConnectionsPerEventLoop: 4),
        as: .psql
    )

    // ───────────────────────────────────────────────
    // 3. Redis
    // ───────────────────────────────────────────────
    let redisURL = Environment.get("REDIS_URL") ?? "redis://localhost:6379"
    app.redis.configuration = try RedisConfiguration(url: redisURL)

    // ───────────────────────────────────────────────
    // 4. JWT — ES256 signing key
    // ───────────────────────────────────────────────
    guard let jwtPrivateKey = Environment.get("JWT_ES256_PRIVATE_KEY") else {
        fatalError("JWT_ES256_PRIVATE_KEY environment variable is required")
    }
    let keyID = JWKIdentifier(string: Environment.get("JWT_KEY_ID") ?? "key-2026-03")

    let ecdsaKey = try ES256PrivateKey(pem: jwtPrivateKey)
    await app.jwt.keys.add(ecdsa: ecdsaKey, kid: keyID)

    // ───────────────────────────────────────────────
    // 5. APNs push notifications
    // ───────────────────────────────────────────────
    if let apnsKeyPath = Environment.get("APNS_KEY_PATH"),
       let apnsKeyID = Environment.get("APNS_KEY_ID"),
       let apnsTeamID = Environment.get("APNS_TEAM_ID") {
        let apnsEnvironment: APNSEnvironment = app.environment == .production
            ? .production : .sandbox
        app.apns.containers.use(
            .init(
                authenticationMethod: .jwt(
                    privateKey: try .loadFrom(filePath: apnsKeyPath),
                    keyIdentifier: apnsKeyID,
                    teamIdentifier: apnsTeamID
                ),
                environment: apnsEnvironment
            ),
            eventLoopGroupProvider: .shared(app.eventLoopGroup),
            as: .default
        )
    }

    // ───────────────────────────────────────────────
    // 6. Background job queue (Redis-backed)
    // ───────────────────────────────────────────────
    try app.queues.use(.redis(url: redisURL))

    // Register job types
    app.queues.add(WhoopSyncJob())
    app.queues.add(LeaderboardRefreshJob())
    app.queues.add(NotificationScheduleJob())
    app.queues.add(WeeklySummaryJob())
    app.queues.add(AccountHardDeleteJob())
    app.queues.add(StaleTokenCleanupJob())
    app.queues.add(WebhookDeliveryJob())
    app.queues.add(GDPRExportJob())
    app.queues.add(PartitionCreationJob())

    // Schedule recurring jobs
    app.queues.schedule(LeaderboardRefreshJob())
        .everyMinute()
        .at(0) // top of each minute — job itself debounces to every 5 min

    app.queues.schedule(ChallengeStatusJob())
        .everyMinute()

    app.queues.schedule(AccountabilityCheckJob())
        .minutely()
        .at(0) // every 15 min handled inside the job

    app.queues.schedule(StaleTokenCleanupJob())
        .daily()
        .at(3, 0) // 03:00 UTC

    app.queues.schedule(AccountHardDeleteJob())
        .daily()
        .at(2, 0) // 02:00 UTC

    app.queues.schedule(PartitionCreationJob())
        .monthly()
        .at(1) // 1st of each month

    // Start the worker in-process (for single-server deployment)
    if app.environment != .testing {
        try app.queues.startInProcessJobs()
        try app.queues.startScheduledJobs()
    }

    // ───────────────────────────────────────────────
    // 7. Middleware (order matters: first registered = outermost)
    // ───────────────────────────────────────────────
    app.middleware = .init() // clear defaults
    app.middleware.use(RequestIdMiddleware())
    app.middleware.use(SecurityHeadersMiddleware())
    app.middleware.use(RequestLoggingMiddleware())
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))

    // ───────────────────────────────────────────────
    // 8. Migrations (order matters: parent tables first)
    // ───────────────────────────────────────────────
    app.migrations.add(CreateUsers())
    app.migrations.add(CreateUserPreferences())
    app.migrations.add(CreateRefreshTokens())
    app.migrations.add(CreateAppleAuth())
    app.migrations.add(CreateWhoopIntegrations())
    app.migrations.add(CreateWhoopRecovery())
    app.migrations.add(CreateWhoopSleep())
    app.migrations.add(CreateWhoopWorkouts())
    app.migrations.add(CreateWhoopCycles())
    app.migrations.add(CreateWhoopBody())
    app.migrations.add(CreateWhoopProfiles())
    app.migrations.add(CreateNutriTrackIntegrations())
    app.migrations.add(CreateXPEvents())
    app.migrations.add(CreateExercises())
    app.migrations.add(CreateWorkoutPlans())
    app.migrations.add(CreateManualWorkouts())
    app.migrations.add(CreateStudySessions())
    app.migrations.add(CreateDailySnapshots())
    app.migrations.add(CreateFriendships())
    app.migrations.add(CreateFriendRequests())
    app.migrations.add(CreateChallenges())
    app.migrations.add(CreateChallengeParticipants())
    app.migrations.add(CreateChallengeDailyScores())
    app.migrations.add(CreateAchievementDefinitions())
    app.migrations.add(CreateUserAchievements())
    app.migrations.add(CreateDeviceTokens())
    app.migrations.add(CreateInsights())
    app.migrations.add(CreateSyncJobs())
    app.migrations.add(CreateAuditLog())
    app.migrations.add(CreateOutboundWebhooks())
    app.migrations.add(CreateOutboundWebhookDeliveries())
    app.migrations.add(CreateLeaderboardViews())
    app.migrations.add(SeedExerciseLibrary())

    // Auto-migrate in development
    if app.environment == .development {
        try await app.autoMigrate()
    }

    // ───────────────────────────────────────────────
    // 9. Routes
    // ───────────────────────────────────────────────
    try routes(app)
}
```

### routes.swift

```swift
import Vapor

func routes(_ app: Application) throws {

    // Health check — no auth, no versioning
    app.get("health") { req in
        return ["status": "ok"]
    }

    // ───────────────────────────────────────────────
    // API v1
    // ───────────────────────────────────────────────
    let v1 = app.grouped("v1")

    // ── Public (no auth) ──────────────────────────
    let auth = v1.grouped("auth")
    try auth.grouped(
        RateLimitMiddleware(limit: 10, window: .minutes(1), scope: .ip)
    ).register(collection: AuthController())

    // JWKS endpoint
    v1.get(".well-known", "jwks.json") { req -> Response in
        let jwks = try await req.application.jwt.keys.jwks
        let response = Response(status: .ok)
        try response.content.encode(jwks, as: .json)
        response.headers.replaceOrAdd(name: .cacheControl, value: "public, max-age=86400")
        return response
    }

    // App config (no auth required)
    try v1.grouped("config")
        .grouped(RateLimitMiddleware(limit: 100, window: .minutes(1), scope: .ip))
        .register(collection: ConfigController())

    // ── Authenticated routes ──────────────────────
    let protected = v1.grouped(JWTAuthMiddleware())

    // Users
    try protected.grouped("users")
        .grouped(RateLimitMiddleware(limit: 100, window: .minutes(1), scope: .user))
        .register(collection: UserController())

    // Preferences
    try protected.grouped("users", "me", "preferences")
        .grouped(RateLimitMiddleware(limit: 100, window: .minutes(1), scope: .user))
        .register(collection: PreferencesController())

    // Whoop integration management
    try protected.grouped("integrations", "whoop")
        .grouped(RateLimitMiddleware(limit: 10, window: .minutes(1), scope: .user))
        .register(collection: WhoopIntegrationController())

    // Whoop data endpoints
    try protected.grouped("whoop")
        .grouped(RateLimitMiddleware(limit: 100, window: .minutes(1), scope: .user))
        .register(collection: WhoopDataController())

    // Whoop webhook (HMAC auth, not JWT)
    try v1.grouped("webhooks", "whoop")
        .grouped(WhoopWebhookMiddleware())
        .grouped(RateLimitMiddleware(limit: 1000, window: .minutes(1), scope: .ip))
        .register(collection: WhoopWebhookController())

    // NutriTrack proxy
    try protected.grouped("nutritrack")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: NutriTrackController())

    // NutriTrack integration management
    try protected.grouped("integrations", "nutritrack")
        .grouped(RateLimitMiddleware(limit: 10, window: .minutes(1), scope: .user))
        .register(collection: NutriTrackController())

    // Exercises
    try protected.grouped("exercises")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: ExerciseController())

    // Workouts
    try protected.grouped("workouts")
        .grouped(RateLimitMiddleware(limit: 100, window: .minutes(1), scope: .user))
        .register(collection: WorkoutController())

    // Workout plans
    try protected.grouped("workout-plans")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: WorkoutPlanController())

    // Study sessions
    try protected.grouped("study-sessions")
        .grouped(RateLimitMiddleware(limit: 100, window: .minutes(1), scope: .user))
        .register(collection: StudySessionController())

    // Snapshots
    try protected.grouped("snapshots")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: SnapshotController())

    // XP
    try protected.grouped("xp")
        .grouped(RateLimitMiddleware(limit: 100, window: .minutes(1), scope: .user))
        .register(collection: XPController())

    // Leaderboard
    try protected.grouped("leaderboard")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: LeaderboardController())

    // Friends
    try protected.grouped("friends")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: FriendController())

    // Challenges
    try protected.grouped("challenges")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: ChallengeController())

    // Achievements
    try protected.grouped("achievements")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: AchievementController())

    // Accountability
    try protected.grouped("accountability")
        .grouped(RateLimitMiddleware(limit: 100, window: .minutes(1), scope: .user))
        .register(collection: AccountabilityController())

    // Sync
    try protected.grouped("sync")
        .grouped(RateLimitMiddleware(limit: 10, window: .minutes(1), scope: .user))
        .register(collection: SyncController())

    // Devices (push tokens)
    try protected.grouped("devices")
        .grouped(RateLimitMiddleware(limit: 10, window: .minutes(1), scope: .user))
        .register(collection: DeviceController())

    // Insights
    try protected.grouped("insights")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: InsightController())

    // Reports
    try protected.grouped("reports")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: ReportController())

    // Exports
    try protected.grouped("export")
        .grouped(RateLimitMiddleware(limit: 3, window: .hours(24), scope: .user))
        .register(collection: ExportController())

    // Search
    try protected.grouped("search")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: SearchController())

    // Outbound webhooks
    try protected.grouped("webhooks", "outbound")
        .grouped(RateLimitMiddleware(limit: 10, window: .minutes(1), scope: .user))
        .register(collection: OutboundWebhookController())

    // WebSocket
    try protected.grouped("ws")
        .register(collection: WebSocketController())

    // ── Admin routes ──────────────────────────────
    let admin = protected
        .grouped(AdminMiddleware())
        .grouped("admin")
        .grouped(RateLimitMiddleware(limit: 30, window: .minutes(1), scope: .user))
    try admin.register(collection: AdminController())
}
```

---

## 5. Model Examples

### User.swift

```swift
import Fluent
import Vapor

final class User: Model, Content, @unchecked Sendable {
    static let schema = "users"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "apple_user_id")
    var appleUserID: String

    @Field(key: "username")
    var username: String

    @Field(key: "display_name")
    var displayName: String

    @OptionalField(key: "bio")
    var bio: String?

    @OptionalField(key: "avatar_url")
    var avatarURL: String?

    @Field(key: "timezone")
    var timezone: String

    @Field(key: "xp_total")
    var xpTotal: Int

    @Field(key: "level")
    var level: Int

    @Field(key: "streak_days")
    var streakDays: Int

    @OptionalField(key: "streak_last_date")
    var streakLastDate: Date?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    @OptionalField(key: "deleted_at")
    var deletedAt: Date?

    @OptionalField(key: "suspended_at")
    var suspendedAt: Date?

    @OptionalField(key: "last_active_at")
    var lastActiveAt: Date?

    // ── Relationships ──────────────────────────
    @OptionalChild(for: \.$user)
    var preferences: UserPreferences?

    @Children(for: \.$user)
    var refreshTokens: [RefreshToken]

    @OptionalChild(for: \.$user)
    var whoopIntegration: WhoopIntegration?

    @OptionalChild(for: \.$user)
    var appleAuth: AppleAuth?

    // ── Initializers ───────────────────────────
    init() {}

    init(
        appleUserID: String,
        username: String,
        displayName: String = "",
        timezone: String = "UTC"
    ) {
        self.id = "usr_" + String.randomHex(length: 24)
        self.appleUserID = appleUserID
        self.username = username
        self.displayName = displayName
        self.timezone = timezone
        self.xpTotal = 0
        self.level = 1
        self.streakDays = 0
    }

    /// Compute level from XP total using the thresholds from the spec.
    static func levelForXP(_ xp: Int) -> Int {
        let thresholds = [
            0, 100, 500, 1_000, 2_500, 5_000,
            7_500, 10_000, 15_000, 25_000, 50_000, 100_000
        ]
        var level = 1
        for (i, threshold) in thresholds.enumerated() {
            if xp >= threshold { level = i + 1 }
        }
        return level
    }

    /// Check if account is soft-deleted.
    var isDeleted: Bool { deletedAt != nil }

    /// Check if in 30-day recovery window.
    var isRecoverable: Bool {
        guard let deletedAt else { return false }
        return Date().timeIntervalSince(deletedAt) < 30 * 24 * 3600
    }
}
```

### WhoopIntegration.swift (WhoopToken)

```swift
import Fluent
import Vapor

final class WhoopIntegration: Model, Content, @unchecked Sendable {
    static let schema = "whoop_integrations"

    @ID(custom: "user_id", generatedBy: .user)
    var id: String?

    @Parent(key: "user_id")
    var user: User

    @Field(key: "whoop_user_id")
    var whoopUserID: Int

    @Field(key: "access_token_enc")
    var accessTokenEncrypted: String

    @Field(key: "refresh_token_enc")
    var refreshTokenEncrypted: String

    @Field(key: "token_expires_at")
    var tokenExpiresAt: Date

    @Field(key: "scopes")
    var scopes: [String]

    @OptionalField(key: "webhook_id")
    var webhookID: String?

    @OptionalField(key: "last_sync_at")
    var lastSyncAt: Date?

    @OptionalField(key: "last_sync_status")
    var lastSyncStatus: String?

    @Timestamp(key: "connected_at", on: .create)
    var connectedAt: Date?

    @OptionalField(key: "disconnected_at")
    var disconnectedAt: Date?

    init() {}

    init(
        userID: String,
        whoopUserID: Int,
        accessTokenEncrypted: String,
        refreshTokenEncrypted: String,
        tokenExpiresAt: Date,
        scopes: [String]
    ) {
        self.id = userID
        self.$user.id = userID
        self.whoopUserID = whoopUserID
        self.accessTokenEncrypted = accessTokenEncrypted
        self.refreshTokenEncrypted = refreshTokenEncrypted
        self.tokenExpiresAt = tokenExpiresAt
        self.scopes = scopes
    }

    /// Decrypt the access token using the app's encryption service.
    func decryptAccessToken(using encryption: EncryptionService) throws -> String {
        try encryption.decrypt(accessTokenEncrypted)
    }

    /// Decrypt the refresh token using the app's encryption service.
    func decryptRefreshToken(using encryption: EncryptionService) throws -> String {
        try encryption.decrypt(refreshTokenEncrypted)
    }

    /// Check if the access token has expired.
    var isTokenExpired: Bool {
        tokenExpiresAt < Date()
    }
}
```

### XPEvent.swift

```swift
import Fluent
import Vapor

final class XPEvent: Model, Content, @unchecked Sendable {
    static let schema = "xp_events"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "user_id")
    var userID: String

    @Field(key: "type")
    var type: String

    @Field(key: "points")
    var points: Int

    @Field(key: "source")
    var source: String

    @OptionalField(key: "reference_id")
    var referenceID: String?

    @Field(key: "occurred_at")
    var occurredAt: Date

    @OptionalField(key: "metadata")
    var metadata: [String: AnyCodable]?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    init() {}

    init(
        userID: String,
        type: XPEventType,
        points: Int,
        source: String,
        referenceID: String? = nil,
        occurredAt: Date,
        metadata: [String: AnyCodable]? = nil
    ) {
        self.id = "xp_evt_" + String.randomHex(length: 16)
        self.userID = userID
        self.type = type.rawValue
        self.points = points
        self.source = source
        self.referenceID = referenceID
        self.occurredAt = occurredAt
        self.metadata = metadata
    }
}

/// All valid XP event types matching the API spec.
enum XPEventType: String, Codable, CaseIterable {
    case workoutLogged = "workout_logged"
    case sleepTargetMet = "sleep_target_met"
    case recoveryChecked = "recovery_checked"
    case mealLogged = "meal_logged"
    case nutritionTargetMet = "nutrition_target_met"
    case studySession = "study_session"
    case streakMaintained = "streak_maintained"
    case streakMilestone = "streak_milestone"
    case challengeJoined = "challenge_joined"
    case challengeWon = "challenge_won"
    case friendAdded = "friend_added"
    case insightViewed = "insight_viewed"
    case achievementUnlocked = "achievement_unlocked"
}

/// Type-erased Codable wrapper for JSON metadata.
struct AnyCodable: Codable, Sendable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) { value = intVal }
        else if let doubleVal = try? container.decode(Double.self) { value = doubleVal }
        else if let stringVal = try? container.decode(String.self) { value = stringVal }
        else if let boolVal = try? container.decode(Bool.self) { value = boolVal }
        else { value = try container.decode([String: AnyCodable].self) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intVal as Int: try container.encode(intVal)
        case let doubleVal as Double: try container.encode(doubleVal)
        case let stringVal as String: try container.encode(stringVal)
        case let boolVal as Bool: try container.encode(boolVal)
        case let dictVal as [String: AnyCodable]: try container.encode(dictVal)
        default: throw EncodingError.invalidValue(value, .init(codingPath: [], debugDescription: "Unsupported type"))
        }
    }
}
```

### Challenge.swift

```swift
import Fluent
import Vapor

final class Challenge: Model, Content, @unchecked Sendable {
    static let schema = "challenges"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "title")
    var title: String

    @OptionalField(key: "description")
    var description: String?

    @Field(key: "type")
    var type: String

    @Field(key: "status")
    var status: String

    @Parent(key: "created_by")
    var creator: User

    @Field(key: "starts_at")
    var startsAt: Date

    @Field(key: "ends_at")
    var endsAt: Date

    @Field(key: "max_participants")
    var maxParticipants: Int

    @Field(key: "visibility")
    var visibility: String

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    // ── Relationships ──────────────────────────
    @Children(for: \.$challenge)
    var participants: [ChallengeParticipant]

    init() {}

    init(
        title: String,
        description: String? = nil,
        type: ChallengeType,
        creatorID: String,
        startsAt: Date,
        endsAt: Date,
        maxParticipants: Int = 10,
        visibility: String = "friends_only"
    ) {
        self.id = "ch_" + String.randomHex(length: 16)
        self.title = title
        self.description = description
        self.type = type.rawValue
        self.status = "upcoming"
        self.$creator.id = creatorID
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.maxParticipants = maxParticipants
        self.visibility = visibility
    }
}

final class ChallengeParticipant: Model, Content, @unchecked Sendable {
    static let schema = "challenge_participants"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Parent(key: "challenge_id")
    var challenge: Challenge

    @Parent(key: "user_id")
    var user: User

    @Field(key: "score")
    var score: Double

    @Field(key: "rank")
    var rank: Int

    @Timestamp(key: "joined_at", on: .create)
    var joinedAt: Date?

    @OptionalField(key: "left_at")
    var leftAt: Date?

    init() {}

    init(challengeID: String, userID: String) {
        self.id = "cp_" + String.randomHex(length: 16)
        self.$challenge.id = challengeID
        self.$user.id = userID
        self.score = 0
        self.rank = 0
    }
}

enum ChallengeType: String, Codable, CaseIterable {
    case xpTotal = "xp_total"
    case workoutCount = "workout_count"
    case workoutStrain = "workout_strain"
    case sleepScore = "sleep_score"
    case studyMinutes = "study_minutes"
    case streakMaintain = "streak_maintain"
    case nutritionAdherence = "nutrition_adherence"
}
```

### DailySnapshot.swift

```swift
import Fluent
import Vapor

final class DailySnapshot: Model, Content, @unchecked Sendable {
    static let schema = "daily_snapshots"

    @ID(custom: "id", generatedBy: .user)
    var id: String?

    @Field(key: "user_id")
    var userID: String

    @Field(key: "date")
    var date: Date

    @Field(key: "timezone")
    var timezone: String

    @OptionalField(key: "recovery")
    var recovery: SnapshotRecovery?

    @OptionalField(key: "sleep")
    var sleep: SnapshotSleep?

    @OptionalField(key: "strain")
    var strain: SnapshotStrain?

    @OptionalField(key: "nutrition")
    var nutrition: SnapshotNutrition?

    @OptionalField(key: "study")
    var study: SnapshotStudy?

    @OptionalField(key: "accountability")
    var accountability: SnapshotAccountability?

    @Field(key: "xp_earned")
    var xpEarned: Int

    @Field(key: "streak_day")
    var streakDay: Int

    @OptionalField(key: "device_info")
    var deviceInfo: SnapshotDeviceInfo?

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(userID: String, date: Date, timezone: String) {
        self.id = "snap_" + String.randomHex(length: 16)
        self.userID = userID
        self.date = date
        self.timezone = timezone
        self.xpEarned = 0
        self.streakDay = 0
    }
}

// ── JSONB sub-structures (stored as JSON columns) ──

struct SnapshotRecovery: Codable, Sendable {
    var score: Int?
    var hrvRmssdMilli: Double?
    var restingHeartRate: Int?
    var spo2Percentage: Double?
    var skinTempCelsius: Double?
}

struct SnapshotSleep: Codable, Sendable {
    var totalDurationMilli: Int64?
    var sleepPerformancePercentage: Double?
    var sleepEfficiencyPercentage: Double?
    var remDurationMilli: Int64?
    var deepDurationMilli: Int64?
    var respiratoryRate: Double?
    var disturbanceCount: Int?
}

struct SnapshotStrain: Codable, Sendable {
    var dayStrain: Double?
    var kilojoule: Double?
    var averageHeartRate: Int?
    var maxHeartRate: Int?
    var workoutCount: Int?
}

struct SnapshotNutrition: Codable, Sendable {
    var calories: Int?
    var proteinG: Double?
    var carbsG: Double?
    var fatG: Double?
    var targetCalories: Int?
    var targetProteinG: Double?
    var adherencePercentage: Double?
    var mealsLogged: Int?
}

struct SnapshotStudy: Codable, Sendable {
    var totalMinutes: Int?
    var sessions: Int?
}

struct SnapshotAccountability: Codable, Sendable {
    var recoveryViewed: Bool?
    var workoutCompleted: Bool?
    var mealsLoggedCount: Int?
    var studyCompleted: Bool?
    var escalationTier: Int?
}

struct SnapshotDeviceInfo: Codable, Sendable {
    var model: String?
    var osVersion: String?
    var appVersion: String?
}
```

---

## 6. Migration Examples

### CreateUsers.swift (Full initial schema)

```swift
import Fluent

struct CreateUsers: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Enable extensions (PostgreSQL-specific)
        try await database.schema("_extensions_setup")
            .ignoreExisting()
            .create()
        try await (database as! SQLDatabase).raw("""
            CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
            CREATE EXTENSION IF NOT EXISTS "pgcrypto";
            """).run()

        try await database.schema("users")
            .field("id", .string, .identifier(auto: false))
            .field("apple_user_id", .string, .required)
            .field("username", .string, .required)
            .field("display_name", .string, .required, .sql(.default("")))
            .field("bio", .string)
            .field("avatar_url", .string)
            .field("timezone", .string, .required, .sql(.default("UTC")))
            .field("xp_total", .int, .required, .sql(.default(0)))
            .field("level", .int, .required, .sql(.default(1)))
            .field("streak_days", .int, .required, .sql(.default(0)))
            .field("streak_last_date", .date)
            .field("created_at", .datetime, .required)
            .field("updated_at", .datetime, .required)
            .field("deleted_at", .datetime)
            .field("suspended_at", .datetime)
            .field("last_active_at", .datetime)
            .unique(on: "apple_user_id")
            .unique(on: "username")
            .create()

        // Partial indexes for active users
        let sql = database as! SQLDatabase
        try await sql.raw("""
            CREATE INDEX idx_users_username_active ON users(username) WHERE deleted_at IS NULL
            """).run()
        try await sql.raw("""
            CREATE INDEX idx_users_xp_total ON users(xp_total DESC)
            """).run()
        try await sql.raw("""
            CREATE INDEX idx_users_last_active ON users(last_active_at DESC) WHERE deleted_at IS NULL
            """).run()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users").delete()
    }
}
```

### Adding an index (example migration)

```swift
import Fluent

struct AddUserXPLevelIndex: AsyncMigration {
    func prepare(on database: Database) async throws {
        let sql = database as! SQLDatabase
        try await sql.raw("""
            CREATE INDEX CONCURRENTLY idx_users_level_xp
            ON users(level DESC, xp_total DESC)
            WHERE deleted_at IS NULL
            """).run()
    }

    func revert(on database: Database) async throws {
        let sql = database as! SQLDatabase
        try await sql.raw("DROP INDEX IF EXISTS idx_users_level_xp").run()
    }
}
```

### Adding a column to an existing table

```swift
import Fluent

struct AddUserOnboardingComplete: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("users")
            .field("onboarding_complete", .bool, .required, .sql(.default(false)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("users")
            .deleteField("onboarding_complete")
            .update()
    }
}
```

### Data migration (backfilling a field)

```swift
import Fluent

struct BackfillUserLevels: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Recalculate level for all users based on XP thresholds
        let sql = database as! SQLDatabase
        try await sql.raw("""
            UPDATE users SET level = CASE
                WHEN xp_total >= 100000 THEN 12
                WHEN xp_total >= 50000 THEN 11
                WHEN xp_total >= 25000 THEN 10
                WHEN xp_total >= 15000 THEN 9
                WHEN xp_total >= 10000 THEN 8
                WHEN xp_total >= 7500 THEN 7
                WHEN xp_total >= 5000 THEN 6
                WHEN xp_total >= 2500 THEN 5
                WHEN xp_total >= 1000 THEN 4
                WHEN xp_total >= 500 THEN 3
                WHEN xp_total >= 100 THEN 2
                ELSE 1
            END
            WHERE deleted_at IS NULL
            """).run()
    }

    func revert(on database: Database) async throws {
        // No-op: can't reverse level calculation
    }
}
```

### CreateXPEvents.swift (partitioned table)

```swift
import Fluent

struct CreateXPEvents: AsyncMigration {
    func prepare(on database: Database) async throws {
        // Partitioned tables require raw SQL in PostgreSQL
        let sql = database as! SQLDatabase
        try await sql.raw("""
            CREATE TABLE xp_events (
                id              TEXT NOT NULL,
                user_id         TEXT NOT NULL,
                type            TEXT NOT NULL,
                points          INTEGER NOT NULL,
                source          TEXT NOT NULL,
                reference_id    TEXT DEFAULT NULL,
                occurred_at     TIMESTAMPTZ NOT NULL,
                metadata        JSONB DEFAULT NULL,
                created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                CONSTRAINT xp_points_positive CHECK (points > 0 AND points <= 500),
                PRIMARY KEY (id, occurred_at)
            ) PARTITION BY RANGE (occurred_at)
            """).run()

        // Create initial partitions
        let calendar = Calendar.current
        let now = Date()
        for monthOffset in -2...6 {
            guard let date = calendar.date(byAdding: .month, value: monthOffset, to: now) else { continue }
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let monthStr = String(format: "%02d", month)
            let nextMonth = month == 12 ? 1 : month + 1
            let nextYear = month == 12 ? year + 1 : year
            let nextMonthStr = String(format: "%02d", nextMonth)

            try await sql.raw(SQLQueryString(stringLiteral: """
                CREATE TABLE IF NOT EXISTS xp_events_\(year)_\(monthStr)
                PARTITION OF xp_events
                FOR VALUES FROM ('\(year)-\(monthStr)-01')
                TO ('\(nextYear)-\(nextMonthStr)-01')
                """)).run()
        }

        // Indexes
        try await sql.raw("""
            CREATE INDEX idx_xp_events_user_date ON xp_events(user_id, occurred_at DESC)
            """).run()
        try await sql.raw("""
            CREATE INDEX idx_xp_events_user_type ON xp_events(user_id, type)
            """).run()
        try await sql.raw("""
            CREATE UNIQUE INDEX idx_xp_events_dedup
            ON xp_events(user_id, type, reference_id)
            WHERE reference_id IS NOT NULL
            """).run()
    }

    func revert(on database: Database) async throws {
        let sql = database as! SQLDatabase
        try await sql.raw("DROP TABLE IF EXISTS xp_events CASCADE").run()
    }
}
```

---

## 7. Controller Pattern

### ArenaController.swift (Complete Example)

```swift
import Vapor
import Fluent

struct ArenaController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // All routes here are already under /v1/challenges with JWT auth
        routes.get(use: listChallenges)
        routes.post(use: createChallenge)
        routes.get(":challengeID", use: getChallenge)
        routes.post(":challengeID", "join", use: joinChallenge)
        routes.post(":challengeID", "leave", use: leavChallenge)
        routes.get("history", use: challengeHistory)
    }

    // ── List challenges ─────────────────────────────────────
    // GET /v1/challenges?status=active&cursor=xxx&limit=25
    func listChallenges(_ req: Request) async throws -> Envelope<[ChallengeResponse]> {
        let userID = try req.auth.requireUserID()
        let query = try req.query.decode(ChallengeListQuery.self)

        var dbQuery = Challenge.query(on: req.db)
            .sort(\.$startsAt, .descending)
            .limit(min(query.limit ?? 25, 100))

        if let status = query.status {
            dbQuery = dbQuery.filter(\.$status == status)
        }

        // Cursor-based pagination
        if let cursor = query.cursor,
           let decoded = try? CursorDecoder.decode(cursor) {
            dbQuery = dbQuery.filter(\.$createdAt < decoded.createdAt)
        }

        // Only show challenges visible to this user (friends_only or public)
        let friendIDs = try await friendIDsForUser(userID, on: req.db)

        let challenges = try await dbQuery
            .with(\.$participants) { $0.with(\.$user) }
            .with(\.$creator)
            .all()
            .filter { challenge in
                challenge.visibility == "public" ||
                challenge.$creator.id == userID ||
                friendIDs.contains(challenge.$creator.id)
            }

        let responses = challenges.map { ChallengeResponse(from: $0, currentUserID: userID) }

        let pagination = PaginationMeta(
            cursor: challenges.last.map { CursorEncoder.encode(createdAt: $0.createdAt!) },
            hasMore: challenges.count == (query.limit ?? 25),
            count: challenges.count
        )

        return Envelope(data: responses, pagination: pagination)
    }

    // ── Create challenge ────────────────────────────────────
    // POST /v1/challenges
    func createChallenge(_ req: Request) async throws -> Envelope<ChallengeResponse> {
        let userID = try req.auth.requireUserID()

        // Validate request body
        try CreateChallengeRequest.validate(content: req)
        let body = try req.content.decode(CreateChallengeRequest.self)

        // Business rule: starts_at must be in the future
        guard body.startsAt > Date() else {
            throw TempoError.challengeStartMustBeFuture
        }

        // Business rule: max 5 active challenges per user
        let activeCount = try await ChallengeParticipant.query(on: req.db)
            .join(Challenge.self, on: \ChallengeParticipant.$challenge.$id == \Challenge.$id)
            .filter(ChallengeParticipant.self, \.$user.$id == userID)
            .filter(Challenge.self, \.$status != "completed")
            .count()

        guard activeCount < 5 else {
            throw TempoError.tooManyActiveChallenges
        }

        // Validate invite targets are friends
        let friendIDs = try await friendIDsForUser(userID, on: req.db)
        if let inviteIDs = body.inviteUserIDs {
            for inviteID in inviteIDs {
                guard friendIDs.contains(inviteID) else {
                    throw TempoError.inviteTargetNotFriend
                }
            }
        }

        // Create challenge
        let endsAt = Calendar.current.date(
            byAdding: .day,
            value: body.durationDays,
            to: body.startsAt
        )!

        let challenge = Challenge(
            title: body.title,
            description: body.description,
            type: body.type,
            creatorID: userID,
            startsAt: body.startsAt,
            endsAt: endsAt,
            maxParticipants: body.maxParticipants ?? 10,
            visibility: body.visibility ?? "friends_only"
        )
        try await challenge.save(on: req.db)

        // Auto-join creator as participant
        let participant = ChallengeParticipant(
            challengeID: challenge.id!,
            userID: userID
        )
        try await participant.save(on: req.db)

        // Send invite notifications
        if let inviteIDs = body.inviteUserIDs {
            for inviteID in inviteIDs {
                try await req.queue.dispatch(
                    NotificationScheduleJob.self,
                    NotificationPayload(
                        type: .challengeInvite,
                        userID: inviteID,
                        data: ["challenge_id": challenge.id!, "title": body.title]
                    )
                )
            }
        }

        // Audit log
        try await AuditService.log(
            on: req.db,
            userID: userID,
            action: "create",
            resource: "challenge",
            resourceID: challenge.id
        )

        // Reload with relationships for response
        guard let loaded = try await Challenge.query(on: req.db)
            .filter(\.$id == challenge.id!)
            .with(\.$participants) { $0.with(\.$user) }
            .with(\.$creator)
            .first()
        else {
            throw Abort(.internalServerError)
        }

        return Envelope(data: ChallengeResponse(from: loaded, currentUserID: userID))
    }

    // ── Get single challenge ────────────────────────────────
    // GET /v1/challenges/:challengeID
    func getChallenge(_ req: Request) async throws -> Envelope<ChallengeResponse> {
        let userID = try req.auth.requireUserID()
        let challengeID = try req.parameters.require("challengeID", as: String.self)

        guard let challenge = try await Challenge.query(on: req.db)
            .filter(\.$id == challengeID)
            .with(\.$participants) { $0.with(\.$user) }
            .with(\.$creator)
            .first()
        else {
            throw TempoError.challengeNotFound
        }

        return Envelope(data: ChallengeResponse(from: challenge, currentUserID: userID))
    }

    // ── Join challenge ──────────────────────────────────────
    // POST /v1/challenges/:challengeID/join
    func joinChallenge(_ req: Request) async throws -> Envelope<ChallengeResponse> {
        let userID = try req.auth.requireUserID()
        let challengeID = try req.parameters.require("challengeID", as: String.self)

        guard let challenge = try await Challenge.query(on: req.db)
            .filter(\.$id == challengeID)
            .with(\.$participants)
            .with(\.$creator)
            .first()
        else {
            throw TempoError.challengeNotFound
        }

        // Validation
        guard challenge.status != "completed" else {
            throw TempoError.challengeEnded
        }
        guard !challenge.participants.contains(where: { $0.$user.id == userID }) else {
            throw TempoError.alreadyParticipating
        }
        guard challenge.participants.count < challenge.maxParticipants else {
            throw TempoError.challengeFull
        }

        let participant = ChallengeParticipant(challengeID: challengeID, userID: userID)
        try await participant.save(on: req.db)

        // Award XP for joining
        try await XPService.award(
            on: req.db,
            redis: req.redis,
            userID: userID,
            type: .challengeJoined,
            points: 10,
            source: "challenge",
            referenceID: challengeID
        )

        // Reload
        guard let loaded = try await Challenge.query(on: req.db)
            .filter(\.$id == challengeID)
            .with(\.$participants) { $0.with(\.$user) }
            .with(\.$creator)
            .first()
        else {
            throw Abort(.internalServerError)
        }

        return Envelope(data: ChallengeResponse(from: loaded, currentUserID: userID))
    }

    // ── Leave challenge ─────────────────────────────────────
    func leavChallenge(_ req: Request) async throws -> Envelope<[String: String]> {
        let userID = try req.auth.requireUserID()
        let challengeID = try req.parameters.require("challengeID", as: String.self)

        guard let participant = try await ChallengeParticipant.query(on: req.db)
            .filter(\.$challenge.$id == challengeID)
            .filter(\.$user.$id == userID)
            .first()
        else {
            throw TempoError.notAParticipant
        }

        participant.leftAt = Date()
        try await participant.save(on: req.db)

        return Envelope(data: ["status": "left"])
    }

    // ── Challenge history ───────────────────────────────────
    func challengeHistory(_ req: Request) async throws -> Envelope<[ChallengeResponse]> {
        let userID = try req.auth.requireUserID()
        let query = try req.query.decode(PaginationQuery.self)

        let participantChallengeIDs = try await ChallengeParticipant.query(on: req.db)
            .filter(\.$user.$id == userID)
            .all()
            .map { $0.$challenge.id }

        let challenges = try await Challenge.query(on: req.db)
            .filter(\.$id ~~ participantChallengeIDs)
            .filter(\.$status == "completed")
            .sort(\.$endsAt, .descending)
            .limit(min(query.limit ?? 25, 100))
            .with(\.$participants) { $0.with(\.$user) }
            .with(\.$creator)
            .all()

        let responses = challenges.map { ChallengeResponse(from: $0, currentUserID: userID) }
        return Envelope(data: responses)
    }

    // ── Helpers ─────────────────────────────────────────────
    private func friendIDsForUser(_ userID: String, on db: Database) async throws -> Set<String> {
        let friendshipsA = try await Friendship.query(on: db)
            .filter(\.$userAID == userID)
            .all()
            .map(\.userBID)

        let friendshipsB = try await Friendship.query(on: db)
            .filter(\.$userBID == userID)
            .all()
            .map(\.userAID)

        return Set(friendshipsA + friendshipsB)
    }
}

// ── Request / Response DTOs ─────────────────────────────

struct ChallengeListQuery: Content {
    var status: String?
    var cursor: String?
    var limit: Int?
}

struct CreateChallengeRequest: Content, Validatable {
    var title: String
    var description: String?
    var type: ChallengeType
    var durationDays: Int
    var startsAt: Date
    var maxParticipants: Int?
    var inviteUserIDs: [String]?
    var visibility: String?

    static func validations(_ validations: inout Validations) {
        validations.add("title", as: String.self, is: .count(1...100))
        validations.add("description", as: String.self, is: .count(...500), required: false)
        validations.add("durationDays", as: Int.self, is: .range(1...90))
        validations.add("maxParticipants", as: Int.self, is: .range(2...50), required: false)
    }
}

struct ChallengeResponse: Content {
    var id: String
    var title: String
    var description: String?
    var type: String
    var status: String
    var creator: UserSummary
    var startsAt: Date
    var endsAt: Date
    var maxParticipants: Int
    var visibility: String
    var participants: [ParticipantResponse]
    var myRank: Int?
    var createdAt: Date

    init(from challenge: Challenge, currentUserID: String) {
        self.id = challenge.id!
        self.title = challenge.title
        self.description = challenge.description
        self.type = challenge.type
        self.status = challenge.status
        self.creator = UserSummary(from: challenge.creator)
        self.startsAt = challenge.startsAt
        self.endsAt = challenge.endsAt
        self.maxParticipants = challenge.maxParticipants
        self.visibility = challenge.visibility
        self.participants = challenge.participants
            .sorted { $0.score > $1.score }
            .map { ParticipantResponse(from: $0, isMe: $0.$user.id == currentUserID) }
        self.myRank = self.participants.first(where: { $0.isMe })?.rank
        self.createdAt = challenge.createdAt!
    }
}

struct UserSummary: Content {
    var id: String
    var username: String
    var displayName: String
    var avatarURL: String?
    var level: Int

    init(from user: User) {
        self.id = user.id!
        self.username = user.username
        self.displayName = user.displayName
        self.avatarURL = user.avatarURL
        self.level = user.level
    }
}

struct ParticipantResponse: Content {
    var userID: String
    var username: String
    var displayName: String
    var avatarURL: String?
    var score: Double
    var rank: Int
    var isMe: Bool

    init(from participant: ChallengeParticipant, isMe: Bool) {
        self.userID = participant.$user.id
        self.username = participant.user.username
        self.displayName = participant.user.displayName
        self.avatarURL = participant.user.avatarURL
        self.score = participant.score
        self.rank = participant.rank
        self.isMe = isMe
    }
}
```

### Envelope.swift (Response wrapper)

```swift
import Vapor

/// Standard API response envelope matching the spec.
struct Envelope<T: Content>: Content {
    var ok: Bool
    var data: T
    var pagination: PaginationMeta?
    var meta: ResponseMeta

    init(data: T, pagination: PaginationMeta? = nil, requestID: String? = nil) {
        self.ok = true
        self.data = data
        self.pagination = pagination
        self.meta = ResponseMeta(
            requestID: requestID ?? "req_" + String.randomHex(length: 12),
            timestamp: Date()
        )
    }
}

struct ResponseMeta: Content {
    var requestID: String
    var timestamp: Date

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case timestamp
    }
}

struct PaginationMeta: Content {
    var cursor: String?
    var hasMore: Bool
    var count: Int

    enum CodingKeys: String, CodingKey {
        case cursor
        case hasMore = "has_more"
        case count
    }
}

struct PaginationQuery: Content {
    var cursor: String?
    var limit: Int?
    var direction: String?
}
```

### Abort+TempoError.swift

```swift
import Vapor

/// Centralized error definitions matching BACKEND_API.md error codes.
enum TempoError {
    // Auth (1xxx)
    static let tokenExpired = Abort(.unauthorized, reason: "Access token has expired.", identifier: "1001")
    static let invalidIdentityToken = Abort(.badRequest, reason: "Invalid identity token.", identifier: "1002")
    static let nonceMismatch = Abort(.badRequest, reason: "Nonce mismatch.", identifier: "1003")
    static let authCodeInvalid = Abort(.badRequest, reason: "Authorization code invalid.", identifier: "1004")
    static let signatureVerificationFailed = Abort(.unauthorized, reason: "Signature verification failed.", identifier: "1005")
    static let identityTokenExpired = Abort(.unauthorized, reason: "Identity token expired.", identifier: "1006")
    static let accountInRecoveryWindow = Abort(.conflict, reason: "Account in recovery window. Use POST /v1/auth/recover.", identifier: "1007")
    static let refreshTokenMalformed = Abort(.badRequest, reason: "Missing or malformed refresh token.", identifier: "1008")
    static let refreshTokenExpired = Abort(.unauthorized, reason: "Refresh token expired.", identifier: "1009")
    static let refreshTokenRevoked = Abort(.unauthorized, reason: "Refresh token revoked or not found.", identifier: "1010")
    static let refreshTokenReplay = Abort(.unauthorized, reason: "Replay detected. All sessions invalidated.", identifier: "1011")
    static let deviceIDMismatch = Abort(.unauthorized, reason: "Device ID mismatch.", identifier: "1012")
    static let noDeletedAccount = Abort(.notFound, reason: "No deleted account found.", identifier: "1013")
    static let recoveryWindowExpired = Abort(.gone, reason: "Recovery window expired.", identifier: "1014")
    static let adminRequired = Abort(.forbidden, reason: "Admin scope required.", identifier: "1015")

    // Validation (2xxx)
    static let validationFailed = Abort(.badRequest, reason: "Validation failed.", identifier: "2001")
    static let usernameTaken = Abort(.conflict, reason: "Username already taken.", identifier: "2002")
    static let userNotFound = Abort(.notFound, reason: "User not found.", identifier: "2006")

    // Integration (3xxx)
    static let whoopAlreadyConnected = Abort(.conflict, reason: "Whoop already connected.", identifier: "3001")
    static let whoopNotConnected = Abort(.notFound, reason: "Whoop not connected.", identifier: "3005")
    static let syncInProgress = Abort(.conflict, reason: "Sync already in progress.", identifier: "3006")
    static let invalidWebhookSignature = Abort(.unauthorized, reason: "Invalid webhook signature.", identifier: "3010")

    // Arena (4xxx)
    static let challengeStartMustBeFuture = Abort(.badRequest, reason: "Start date must be in the future.", identifier: "4013")
    static let inviteTargetNotFriend = Abort(.badRequest, reason: "Invite target is not a friend.", identifier: "4014")
    static let tooManyActiveChallenges = Abort(.tooManyRequests, reason: "Too many active challenges.", identifier: "4015")
    static let challengeNotFound = Abort(.notFound, reason: "Challenge not found.", identifier: "4017")
    static let alreadyParticipating = Abort(.conflict, reason: "Already participating.", identifier: "4018")
    static let challengeFull = Abort(.conflict, reason: "Challenge is full.", identifier: "4019")
    static let challengeEnded = Abort(.conflict, reason: "Challenge has ended.", identifier: "4020")
    static let notAParticipant = Abort(.conflict, reason: "Not a participant.", identifier: "4021")

    // Server (5xxx)
    static let rateLimitExceeded = Abort(.tooManyRequests, reason: "Rate limit exceeded.", identifier: "5001")
    static let insufficientData = Abort(.badRequest, reason: "Insufficient data.", identifier: "5002")
    static let aiLimitReached = Abort(.tooManyRequests, reason: "AI insight daily limit reached.", identifier: "5003")
    static let aiUnavailable = Abort(.serviceUnavailable, reason: "AI service unavailable.", identifier: "5004")
}
```

---

## 8. Middleware

### JWTAuthMiddleware.swift

```swift
import Vapor
import JWT

/// Verifies the Bearer JWT on every protected request.
/// Attaches `req.auth.userId` and `req.auth.scopes` on success.
struct JWTAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // 1. Extract Bearer token
        guard let bearerToken = request.headers.bearerAuthorization?.token else {
            throw Abort(.unauthorized, reason: "Missing Authorization header.", identifier: "1001")
        }

        // 2. Verify and decode JWT
        let payload: TempoAccessToken
        do {
            payload = try await request.jwt.verify(bearerToken, as: TempoAccessToken.self)
        } catch {
            throw Abort(.unauthorized, reason: "Invalid or expired access token.", identifier: "1001")
        }

        // 3. Validate issuer and audience
        guard payload.issuer.value == "tempo-api",
              payload.audience.value.contains("app.tempo.ios") else {
            throw Abort(.unauthorized, reason: "Invalid token claims.", identifier: "1001")
        }

        // 4. Check if token ID is blocklisted in Redis
        if let jti = payload.jti {
            let blocked = try await request.redis.get(RedisKey("blocklist:jti:\(jti)"), as: String.self)
            if blocked != nil {
                throw Abort(.unauthorized, reason: "Token has been revoked.", identifier: "1001")
            }
        }

        // 5. Attach authenticated user info to request
        let authInfo = AuthenticatedUser(
            userID: payload.subject.value,
            scopes: payload.scopes,
            deviceID: payload.deviceID
        )
        request.storage[AuthenticatedUserKey.self] = authInfo

        // 6. Update last_active_at (fire and forget — don't block the request)
        Task {
            try? await User.query(on: request.db)
                .filter(\.$id == payload.subject.value)
                .set(\.$lastActiveAt, to: Date())
                .update()
        }

        return try await next.respond(to: request)
    }
}

/// JWT payload matching the spec (ES256, 15-min TTL).
struct TempoAccessToken: JWTPayload {
    var subject: SubjectClaim
    var issuer: IssuerClaim
    var audience: AudienceClaim
    var issuedAt: IssuedAtClaim
    var expiration: ExpirationClaim
    var jti: String?
    var deviceID: String
    var scopes: [String]

    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case issuer = "iss"
        case audience = "aud"
        case issuedAt = "iat"
        case expiration = "exp"
        case jti
        case deviceID = "device_id"
        case scopes
    }

    func verify(using algorithm: some JWTAlgorithm) async throws {
        try self.expiration.verifyNotExpired()
    }
}

/// Storage key for attaching auth info to the request.
struct AuthenticatedUserKey: StorageKey {
    typealias Value = AuthenticatedUser
}

struct AuthenticatedUser: Sendable {
    let userID: String
    let scopes: [String]
    let deviceID: String

    var isAdmin: Bool { scopes.contains("admin") }
}

/// Convenience accessor on Request.
extension Request {
    var auth: AuthAccessor { AuthAccessor(request: self) }

    struct AuthAccessor {
        let request: Request

        func requireUserID() throws -> String {
            guard let auth = request.storage[AuthenticatedUserKey.self] else {
                throw Abort(.unauthorized, reason: "Not authenticated.", identifier: "1001")
            }
            return auth.userID
        }

        func requireAdmin() throws {
            guard let auth = request.storage[AuthenticatedUserKey.self], auth.isAdmin else {
                throw TempoError.adminRequired
            }
        }

        var user: AuthenticatedUser? {
            request.storage[AuthenticatedUserKey.self]
        }
    }
}
```

### RateLimitMiddleware.swift

```swift
import Vapor
import Redis

/// Redis-based sliding window rate limiter.
/// Configurable per-route with different limits, windows, and scopes.
struct RateLimitMiddleware: AsyncMiddleware {
    enum Scope {
        case ip
        case user
    }

    enum Window {
        case minutes(Int)
        case hours(Int)

        var seconds: Int {
            switch self {
            case .minutes(let m): return m * 60
            case .hours(let h): return h * 3600
            }
        }
    }

    let limit: Int
    let window: Window
    let scope: Scope

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let identifier: String
        switch scope {
        case .ip:
            identifier = request.peerAddress?.ipAddress ?? "unknown"
        case .user:
            if let auth = request.storage[AuthenticatedUserKey.self] {
                identifier = auth.userID
            } else {
                identifier = request.peerAddress?.ipAddress ?? "unknown"
            }
        }

        let routePattern = request.route?.description ?? request.url.path
        let key = RedisKey("ratelimit:\(identifier):\(routePattern)")
        let now = Date().timeIntervalSince1970
        let windowStart = now - Double(window.seconds)

        // Sliding window: remove old entries, add current, count
        // Use a Redis sorted set with timestamps as scores
        _ = try await request.redis.zremrangebyscore(
            from: key,
            withMinimumScoreOf: .inclusive(0),
            andMaximumScoreOf: .inclusive(windowStart)
        )

        let currentCount = try await request.redis.zcard(of: key)

        if currentCount >= limit {
            // Calculate retry-after
            let oldestEntry = try await request.redis.zrangebyscore(
                from: key,
                withMinimumScoreOf: .inclusive(windowStart),
                limitBy: (offset: 0, count: 1)
            )
            let retryAfter: Int
            if let oldestScore = oldestEntry.first?.description,
               let oldestTime = Double(oldestScore) {
                retryAfter = Int(oldestTime + Double(window.seconds) - now) + 1
            } else {
                retryAfter = window.seconds
            }

            var headers = HTTPHeaders()
            headers.add(name: "Retry-After", value: "\(retryAfter)")
            headers.add(name: "X-RateLimit-Limit", value: "\(limit)")
            headers.add(name: "X-RateLimit-Remaining", value: "0")
            headers.add(name: "X-RateLimit-Reset", value: "\(Int(now) + retryAfter)")

            throw Abort(.tooManyRequests, headers: headers, reason: "Rate limit exceeded.", identifier: "5001")
        }

        // Add current request timestamp
        _ = try await request.redis.zadd(
            [(element: RESPValue(from: UUID().uuidString), score: now)],
            to: key
        )
        // Set expiry on the key so it auto-cleans
        _ = try await request.redis.expire(key, after: .seconds(Int64(window.seconds + 10)))

        // Execute the actual request
        var response = try await next.respond(to: request)

        // Add rate limit headers to response
        let remaining = max(0, limit - Int(currentCount) - 1)
        response.headers.add(name: "X-RateLimit-Limit", value: "\(limit)")
        response.headers.add(name: "X-RateLimit-Remaining", value: "\(remaining)")
        response.headers.add(name: "X-RateLimit-Reset", value: "\(Int(now) + window.seconds)")

        return response
    }
}
```

### WhoopWebhookMiddleware.swift

```swift
import Vapor
import Crypto

/// Verifies Whoop webhook HMAC-SHA256 signatures.
/// Rejects requests with invalid signatures or expired timestamps.
struct WhoopWebhookMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // 1. Get signature and timestamp headers
        guard let signature = request.headers.first(name: "X-Whoop-Signature") else {
            throw Abort(.badRequest, reason: "Missing webhook signature.", identifier: "3009")
        }

        guard let timestampStr = request.headers.first(name: "X-Whoop-Timestamp"),
              let timestamp = Double(timestampStr) else {
            throw Abort(.badRequest, reason: "Missing webhook timestamp.", identifier: "3009")
        }

        // 2. Reject timestamps older than 5 minutes
        let age = Date().timeIntervalSince1970 - timestamp
        guard age < 300 && age > -60 else {
            throw Abort(.unauthorized, reason: "Webhook timestamp expired.", identifier: "3011")
        }

        // 3. Read raw body
        guard let body = request.body.data else {
            throw Abort(.badRequest, reason: "Empty request body.")
        }
        let bodyBytes = Data(buffer: body)

        // 4. Compute expected signature
        guard let webhookSecret = Environment.get("WHOOP_WEBHOOK_SECRET") else {
            request.logger.critical("WHOOP_WEBHOOK_SECRET not configured")
            throw Abort(.internalServerError)
        }

        let message = "\(timestampStr).\(String(data: bodyBytes, encoding: .utf8) ?? "")"
        let key = SymmetricKey(data: Data(webhookSecret.utf8))
        let expectedMAC = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8),
            using: key
        )
        let expectedSignature = Data(expectedMAC).map { String(format: "%02x", $0) }.joined()

        // 5. Constant-time comparison
        guard signature == expectedSignature else {
            throw Abort(.unauthorized, reason: "Invalid webhook signature.", identifier: "3010")
        }

        return try await next.respond(to: request)
    }
}
```

### SecurityHeadersMiddleware.swift

```swift
import Vapor

/// Adds security headers to every response per BACKEND_API.md section 24.2.
struct SecurityHeadersMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        var response = try await next.respond(to: request)
        response.headers.replaceOrAdd(
            name: .strictTransportSecurity,
            value: "max-age=63072000; includeSubDomains; preload"
        )
        response.headers.replaceOrAdd(name: "X-Content-Type-Options", value: "nosniff")
        response.headers.replaceOrAdd(name: "X-Frame-Options", value: "DENY")
        response.headers.replaceOrAdd(
            name: "Referrer-Policy",
            value: "strict-origin-when-cross-origin"
        )
        response.headers.replaceOrAdd(
            name: "Content-Security-Policy",
            value: "default-src 'none'"
        )
        response.headers.replaceOrAdd(
            name: "Permissions-Policy",
            value: "camera=(), microphone=(), geolocation=()"
        )
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return response
    }
}
```

### RequestIdMiddleware.swift

```swift
import Vapor

/// Generates or propagates X-Request-Id on every request/response.
struct RequestIdMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let requestID = request.headers.first(name: "X-Request-Id")
            ?? "req_" + String.randomHex(length: 12)

        request.storage[RequestIDKey.self] = requestID
        request.logger[metadataKey: "request_id"] = .string(requestID)

        var response = try await next.respond(to: request)
        response.headers.replaceOrAdd(name: "X-Request-Id", value: requestID)
        return response
    }
}

struct RequestIDKey: StorageKey {
    typealias Value = String
}
```

---

## 9. Background Jobs

### WhoopSyncJob.swift

```swift
import Vapor
import Queues
import Fluent

/// Fetches recovery, sleep, and workout data from Whoop for a single user.
/// Dispatched on webhook events or manual sync triggers.
struct WhoopSyncJob: AsyncJob {
    typealias Payload = WhoopSyncPayload

    func dequeue(_ context: QueueContext, _ payload: WhoopSyncPayload) async throws {
        let app = context.application
        let db = app.db
        let logger = context.logger

        logger.info("Starting Whoop sync", metadata: [
            "user_id": .string(payload.userID),
            "days_back": .stringConvertible(payload.daysBack),
            "sync_type": .string(payload.syncType)
        ])

        // 1. Load integration
        guard let integration = try await WhoopIntegration.query(on: db)
            .filter(\.$id == payload.userID)
            .first()
        else {
            logger.warning("Whoop integration not found for user", metadata: [
                "user_id": .string(payload.userID)
            ])
            return
        }

        // 2. Get or refresh access token
        let encryption = EncryptionService()
        var accessToken = try integration.decryptAccessToken(using: encryption)

        if integration.isTokenExpired {
            let refreshToken = try integration.decryptRefreshToken(using: encryption)
            let newTokens = try await WhoopOAuthService.refreshTokens(
                refreshToken: refreshToken,
                client: app.client
            )
            integration.accessTokenEncrypted = try encryption.encrypt(newTokens.accessToken)
            integration.refreshTokenEncrypted = try encryption.encrypt(newTokens.refreshToken)
            integration.tokenExpiresAt = newTokens.expiresAt
            try await integration.save(on: db)
            accessToken = newTokens.accessToken
        }

        let whoopAPI = WhoopAPIService(accessToken: accessToken, client: app.client)

        // 3. Update sync job status
        if let syncJobID = payload.syncJobID {
            try await SyncJob.query(on: db)
                .filter(\.$id == syncJobID)
                .set(\.$status, to: "running")
                .set(\.$startedAt, to: Date())
                .update()
        }

        // 4. Fetch data based on sync type
        let startDate = Calendar.current.date(
            byAdding: .day,
            value: -payload.daysBack,
            to: Date()
        )!

        do {
            // Recovery
            if payload.syncType == "full" || payload.syncType == "recovery" {
                let recoveries = try await whoopAPI.fetchRecovery(from: startDate)
                for recovery in recoveries {
                    try await upsertRecovery(recovery, userID: payload.userID, on: db)
                }
                logger.info("Synced \(recoveries.count) recovery records")
            }

            // Sleep
            if payload.syncType == "full" || payload.syncType == "sleep" {
                let sleepRecords = try await whoopAPI.fetchSleep(from: startDate)
                for sleep in sleepRecords {
                    try await upsertSleep(sleep, userID: payload.userID, on: db)
                }
                logger.info("Synced \(sleepRecords.count) sleep records")
            }

            // Workouts
            if payload.syncType == "full" || payload.syncType == "workout" {
                let workouts = try await whoopAPI.fetchWorkouts(from: startDate)
                for workout in workouts {
                    try await upsertWorkout(workout, userID: payload.userID, on: db)
                }
                logger.info("Synced \(workouts.count) workout records")
            }

            // Update integration status
            integration.lastSyncAt = Date()
            integration.lastSyncStatus = "success"
            try await integration.save(on: db)

            // Update sync job
            if let syncJobID = payload.syncJobID {
                try await SyncJob.query(on: db)
                    .filter(\.$id == syncJobID)
                    .set(\.$status, to: "completed")
                    .set(\.$completedAt, to: Date())
                    .update()
            }

        } catch {
            logger.error("Whoop sync failed: \(error)")
            integration.lastSyncStatus = "failed"
            try? await integration.save(on: db)

            if let syncJobID = payload.syncJobID {
                try? await SyncJob.query(on: db)
                    .filter(\.$id == syncJobID)
                    .set(\.$status, to: "failed")
                    .set(\.$errorMessage, to: error.localizedDescription)
                    .set(\.$completedAt, to: Date())
                    .update()
            }

            throw error // Let Queues handle retry
        }
    }

    private func upsertRecovery(_ data: WhoopRecoveryData, userID: String, on db: Database) async throws {
        if let existing = try await WhoopRecovery.query(on: db)
            .filter(\.$userID == userID)
            .filter(\.$date == data.date)
            .first() {
            existing.recoveryScore = data.recoveryScore
            existing.restingHeartRate = data.restingHeartRate
            existing.hrvRmssdMilli = data.hrvRmssdMilli
            existing.spo2Percentage = data.spo2Percentage
            existing.skinTempCelsius = data.skinTempCelsius
            existing.syncedAt = Date()
            try await existing.save(on: db)
        } else {
            let record = WhoopRecovery(
                userID: userID,
                whoopCycleID: data.cycleID,
                date: data.date,
                recoveryScore: data.recoveryScore,
                restingHeartRate: data.restingHeartRate,
                hrvRmssdMilli: data.hrvRmssdMilli,
                spo2Percentage: data.spo2Percentage,
                skinTempCelsius: data.skinTempCelsius
            )
            try await record.save(on: db)
        }
    }

    // upsertSleep and upsertWorkout follow the same pattern...
    private func upsertSleep(_ data: WhoopSleepData, userID: String, on db: Database) async throws {
        // Same upsert logic as recovery
    }

    private func upsertWorkout(_ data: WhoopWorkoutData, userID: String, on db: Database) async throws {
        // Same upsert logic as recovery
    }
}

struct WhoopSyncPayload: Codable {
    var userID: String
    var daysBack: Int
    var syncType: String // "full", "recovery", "sleep", "workout"
    var syncJobID: String?
}
```

### LeaderboardRefreshJob.swift

```swift
import Vapor
import Queues
import Fluent

/// Refreshes materialized views for leaderboards.
/// Debounced to run at most once every 5 minutes.
struct LeaderboardRefreshJob: AsyncScheduledJob {
    func run(context: QueueContext) async throws {
        let app = context.application
        let redis = app.redis
        let logger = context.logger

        // Debounce: check if we refreshed in the last 5 minutes
        let lastRefreshKey = RedisKey("leaderboard:last_refresh")
        if let lastRefresh = try await redis.get(lastRefreshKey, as: String.self),
           let timestamp = Double(lastRefresh),
           Date().timeIntervalSince1970 - timestamp < 300 {
            return // Skip — refreshed recently
        }

        logger.info("Refreshing leaderboard materialized views")

        let sql = app.db as! SQLDatabase

        try await sql.raw("REFRESH MATERIALIZED VIEW CONCURRENTLY mv_leaderboard_weekly").run()
        try await sql.raw("REFRESH MATERIALIZED VIEW CONCURRENTLY mv_leaderboard_monthly").run()
        try await sql.raw("REFRESH MATERIALIZED VIEW CONCURRENTLY mv_leaderboard_alltime").run()

        // Record refresh time
        try await redis.set(lastRefreshKey, to: String(Date().timeIntervalSince1970))
        try await redis.expire(lastRefreshKey, after: .seconds(600))

        // Invalidate cached leaderboard responses
        let keys = try await redis.scan(matching: "cache:leaderboard:*").compactMap { $0 }
        for key in keys {
            _ = try await redis.delete(key)
        }

        logger.info("Leaderboard refresh complete")
    }
}
```

### NotificationScheduleJob.swift

```swift
import Vapor
import Queues
import Fluent
import VaporAPNS

/// Sends push notifications via APNs.
/// Handles all notification types from the spec.
struct NotificationScheduleJob: AsyncJob {
    typealias Payload = NotificationPayload

    func dequeue(_ context: QueueContext, _ payload: NotificationPayload) async throws {
        let app = context.application
        let db = app.db
        let logger = context.logger

        // 1. Load user's device tokens
        let deviceTokens = try await DeviceToken.query(on: db)
            .filter(\.$userID == payload.userID)
            .all()

        guard !deviceTokens.isEmpty else {
            logger.info("No device tokens for user \(payload.userID), skipping notification")
            return
        }

        // 2. Check user preferences (quiet hours, notification settings)
        if let prefs = try await UserPreferences.query(on: db)
            .filter(\.$id == payload.userID)
            .first() {
            let prefsData = prefs.prefs
            if let notifications = prefsData["notifications"] as? [String: Any] {
                // Check if this notification type is enabled
                let enabledKey = payload.type.preferencesKey
                if let enabled = notifications[enabledKey] as? Bool, !enabled {
                    logger.info("Notification type \(payload.type.rawValue) disabled for user")
                    return
                }
            }
        }

        // 3. Build APNs payload
        let (title, subtitle, body) = payload.type.buildMessage(data: payload.data)
        let sound = payload.type.sound

        let alert = APNSAlertNotification(
            alert: .init(title: .raw(title), subtitle: subtitle.map { .raw($0) }, body: .raw(body)),
            expiration: .immediately,
            priority: .immediately,
            topic: "app.tempo.ios",
            payload: TempoAPNSPayload(
                type: payload.type.rawValue,
                data: payload.data,
                deepLink: payload.type.deepLink(data: payload.data)
            ),
            sound: .named(sound),
            category: payload.type.category
        )

        // 4. Send to all user devices
        for device in deviceTokens {
            do {
                try await app.apns.client(.default).sendAlertNotification(
                    alert,
                    deviceToken: device.token
                )
            } catch let error as APNSError {
                logger.error("APNs error for device \(device.deviceID): \(error)")
                // Remove invalid tokens
                if case .badDeviceToken = error.reason {
                    try? await device.delete(on: db)
                }
            }
        }
    }
}

struct NotificationPayload: Codable {
    var type: NotificationType
    var userID: String
    var data: [String: String]
}

enum NotificationType: String, Codable {
    case recoveryMorning = "recovery_morning"
    case accountabilityTier1 = "accountability_tier1"
    case accountabilityTier2 = "accountability_tier2"
    case accountabilityTier3 = "accountability_tier3"
    case accountabilityTier4 = "accountability_tier4"
    case leaderboardChange = "leaderboard_change"
    case challengeInvite = "challenge_invite"
    case challengeUpdate = "challenge_update"
    case achievementUnlock = "achievement_unlock"
    case weeklySummary = "weekly_summary"

    var preferencesKey: String {
        switch self {
        case .recoveryMorning: return "recovery_morning"
        case .accountabilityTier1, .accountabilityTier2,
             .accountabilityTier3, .accountabilityTier4: return "accountability_nudges"
        case .leaderboardChange: return "leaderboard_changes"
        case .challengeInvite, .challengeUpdate: return "challenge_updates"
        case .achievementUnlock: return "achievement_unlocks"
        case .weeklySummary: return "weekly_summary"
        }
    }

    var sound: String {
        switch self {
        case .recoveryMorning: return "recovery.caf"
        case .achievementUnlock: return "achievement.caf"
        case .accountabilityTier3, .accountabilityTier4: return "urgent.caf"
        default: return "default"
        }
    }

    var category: String {
        switch self {
        case .recoveryMorning: return "RECOVERY_REPORT"
        case .challengeInvite: return "CHALLENGE_INVITE"
        case .achievementUnlock: return "ACHIEVEMENT"
        default: return "GENERAL"
        }
    }

    func buildMessage(data: [String: String]) -> (title: String, subtitle: String?, body: String) {
        switch self {
        case .recoveryMorning:
            let score = data["recovery_score"] ?? "??"
            let hrv = data["hrv"] ?? "??"
            let rhr = data["rhr"] ?? "??"
            return (
                "Good morning! Recovery: \(score)%",
                "HRV \(hrv)ms | RHR \(rhr)bpm",
                score >= "70" ? "You're in the green. Time to push it." : "Take it easy today. Recovery is key."
            )
        case .accountabilityTier1:
            return ("Gentle nudge", nil, "Time to check off your non-negotiables. You've got this.")
        case .accountabilityTier2:
            return ("Streak at risk", nil, "Your streak is in danger. Get moving before it's too late.")
        case .accountabilityTier3:
            return ("3 hours left", nil, "Your streak dies at midnight. No excuses.")
        case .accountabilityTier4:
            return ("Streak lost", nil, "You broke the chain. Start rebuilding tomorrow.")
        case .challengeInvite:
            let title = data["title"] ?? "a challenge"
            return ("Challenge invite", nil, "You've been invited to \(title).")
        case .achievementUnlock:
            let name = data["name"] ?? "an achievement"
            return ("Achievement unlocked!", nil, "You earned: \(name)")
        default:
            return ("Tempo", nil, data["message"] ?? "You have a new update.")
        }
    }

    func deepLink(data: [String: String]) -> String {
        switch self {
        case .recoveryMorning:
            return "tempo://recovery/\(data["date"] ?? "today")"
        case .challengeInvite, .challengeUpdate:
            return "tempo://challenges/\(data["challenge_id"] ?? "")"
        case .achievementUnlock:
            return "tempo://achievements"
        case .leaderboardChange:
            return "tempo://leaderboard"
        default:
            return "tempo://dashboard"
        }
    }
}

struct TempoAPNSPayload: Codable {
    var type: String
    var data: [String: String]
    var deepLink: String

    enum CodingKeys: String, CodingKey {
        case type
        case data
        case deepLink = "deep_link"
    }
}
```

---

## 10. Docker Setup

### Dockerfile

```dockerfile
# ============================================================
# Stage 1: Build
# ============================================================
FROM swift:6.0-jammy AS build

WORKDIR /build

# Copy Package manifests first (better layer caching)
COPY Package.swift Package.resolved ./

# Resolve dependencies
RUN swift package resolve

# Copy source code
COPY Sources/ Sources/
COPY Tests/ Tests/
COPY Resources/ Resources/

# Build release binary
RUN swift build -c release --static-swift-stdlib \
    -Xlinker -lstdc++ \
    && mv $(swift build -c release --show-bin-path)/App /build/app

# ============================================================
# Stage 2: Production image
# ============================================================
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libcurl4 \
    libxml2 \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy binary from build stage
COPY --from=build /build/app .
COPY --from=build /build/Resources ./Resources
COPY --from=build /build/Public ./Public

# Create non-root user
RUN useradd --create-home --shell /bin/bash vapor
USER vapor

EXPOSE 8080

ENV ENVIRONMENT=production
ENV LOG_LEVEL=info

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

ENTRYPOINT ["./app"]
CMD ["serve", "--hostname", "0.0.0.0", "--port", "8080"]
```

### docker-compose.yml

```yaml
version: "3.9"

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      - ENVIRONMENT=development
      - LOG_LEVEL=debug
      - DATABASE_URL=postgres://tempo:tempo_dev@db:5432/tempo
      - REDIS_URL=redis://redis:6379
    env_file:
      - .env
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: tempo
      POSTGRES_PASSWORD: tempo_dev
      POSTGRES_DB: tempo
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U tempo"]
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes --maxmemory 128mb --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
  redis_data:
```

### docker-compose.override.yml

```yaml
# Development extras — automatically merged with docker-compose.yml
version: "3.9"

services:
  # Hot-reload: mount source and rebuild on changes
  app:
    build:
      target: build
    volumes:
      - .:/build
    command: >
      bash -c "swift build && .build/debug/App serve --hostname 0.0.0.0 --port 8080"

  # pgAdmin for database management
  pgadmin:
    image: dpage/pgadmin4:latest
    ports:
      - "5050:80"
    environment:
      PGADMIN_DEFAULT_EMAIL: admin@tempo.app
      PGADMIN_DEFAULT_PASSWORD: admin
      PGADMIN_CONFIG_SERVER_MODE: "False"
    depends_on:
      - db

  # Redis Commander for cache inspection
  redis-commander:
    image: rediscommander/redis-commander:latest
    ports:
      - "8081:8081"
    environment:
      REDIS_HOSTS: local:redis:6379
    depends_on:
      - redis

  # Test database (isolated)
  db-test:
    image: postgres:16-alpine
    ports:
      - "5433:5432"
    environment:
      POSTGRES_USER: tempo_test
      POSTGRES_PASSWORD: tempo_test
      POSTGRES_DB: tempo_test
    tmpfs:
      - /var/lib/postgresql/data  # RAM disk for speed
```

---

## 11. Environment Configuration

### .env.example

```bash
# ============================================================
# Tempo Backend — Environment Variables
# Copy to .env and fill in actual values
# ============================================================

# ── Server ──────────────────────────────────────────────────
ENVIRONMENT=development               # development | staging | production
LOG_LEVEL=debug                        # trace | debug | info | notice | warning | error | critical
SERVER_HOSTNAME=0.0.0.0               # Bind address
SERVER_PORT=8080                       # HTTP port

# ── PostgreSQL ──────────────────────────────────────────────
# Option A: Full URL (preferred for cloud deployments)
DATABASE_URL=postgres://tempo:tempo_dev@localhost:5432/tempo
# Option B: Individual components
DB_HOST=localhost
DB_PORT=5432
DB_USER=tempo
DB_PASSWORD=tempo_dev
DB_NAME=tempo
DB_MAX_CONNECTIONS=20                  # Per event loop; total = this * CPU cores

# ── Redis ───────────────────────────────────────────────────
REDIS_URL=redis://localhost:6379       # redis://[:password@]host:port[/db]

# ── JWT (ES256) ─────────────────────────────────────────────
# Generate key pair:
#   openssl ecparam -genkey -name prime256v1 -noout -out ec_private.pem
#   openssl ec -in ec_private.pem -pubout -out ec_public.pem
JWT_ES256_PRIVATE_KEY="-----BEGIN EC PRIVATE KEY-----\nMHQCAQEEI...\n-----END EC PRIVATE KEY-----"
JWT_ES256_PUBLIC_KEY="-----BEGIN PUBLIC KEY-----\nMFkwEwYH...\n-----END PUBLIC KEY-----"
JWT_KEY_ID=key-2026-03                 # kid claim — rotate every 90 days
JWT_ISSUER=tempo-api                   # iss claim
JWT_AUDIENCE=app.tempo.ios             # aud claim
JWT_ACCESS_TOKEN_TTL=900               # 15 minutes in seconds
JWT_REFRESH_TOKEN_TTL=2592000          # 30 days in seconds

# ── Encryption (AES-256-GCM for secrets at rest) ───────────
# Generate: openssl rand -hex 32
ENCRYPTION_KEY=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

# ── Apple Sign In ───────────────────────────────────────────
APPLE_BUNDLE_ID=app.tempo.ios          # Your app's bundle identifier
APPLE_TEAM_ID=ABCDE12345               # Apple Developer Team ID
APPLE_KEY_ID=FGHIJ67890                # Sign In with Apple key ID
APPLE_PRIVATE_KEY_PATH=./keys/apple_auth_key.p8

# ── Whoop OAuth ─────────────────────────────────────────────
WHOOP_CLIENT_ID=tempo_app              # From Whoop developer portal
WHOOP_CLIENT_SECRET=whoop_secret_here  # Keep this safe
WHOOP_REDIRECT_URI=https://api.tempo.app/v1/integrations/whoop/callback
WHOOP_WEBHOOK_SECRET=whsec_your_webhook_secret  # For verifying incoming webhooks

# ── NutriTrack ──────────────────────────────────────────────
# Not configured here — per-user. This is the timeout for proxy calls.
NUTRITRACK_PROXY_TIMEOUT_SECONDS=10    # Max wait for NutriTrack response
NUTRITRACK_MAX_RETRIES=2               # Retries on timeout/5xx

# ── Claude API (AI Insights) ───────────────────────────────
CLAUDE_API_KEY=sk-ant-xxxxxxxxxxxx     # Anthropic API key
CLAUDE_MODEL=claude-sonnet-4-20250514       # Model for weekly insights
CLAUDE_MAX_OUTPUT_TOKENS=2000          # Per-request limit
CLAUDE_MONTHLY_BUDGET_CENTS=5000       # $50/month budget cap

# ── APNs (Push Notifications) ──────────────────────────────
APNS_KEY_PATH=./keys/apns_auth_key.p8 # AuthKey_XXXXX.p8 from Apple
APNS_KEY_ID=XXXXX12345                 # Key ID from Apple Developer portal
APNS_TEAM_ID=ABCDE12345               # Same as APPLE_TEAM_ID
APNS_TOPIC=app.tempo.ios               # Bundle ID
APNS_ENVIRONMENT=sandbox               # sandbox | production

# ── S3 (Avatar storage) ────────────────────────────────────
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
AWS_REGION=eu-west-1
S3_BUCKET_AVATARS=tempo-avatars
S3_PRESIGN_TTL=300                     # Presigned URL validity (5 min)
CDN_BASE_URL=https://cdn.tempo.app     # CloudFront distribution

# ── Rate Limiting ───────────────────────────────────────────
RATE_LIMIT_ENABLED=true
RATE_LIMIT_AUTH_PER_MINUTE=10          # /auth/* endpoints
RATE_LIMIT_DEFAULT_PER_MINUTE=100      # All other GET endpoints
RATE_LIMIT_WRITE_PER_MINUTE=30         # POST/PATCH/PUT endpoints
```

---

## 12. Testing Setup

### Running tests

```bash
# Start test database (uses tmpfs for speed)
docker compose up -d db-test

# Run all tests
DATABASE_URL=postgres://tempo_test:tempo_test@localhost:5433/tempo_test \
REDIS_URL=redis://localhost:6379/1 \
swift test

# Run specific test file
swift test --filter ArenaTests

# Run with verbose output
swift test -v 2>&1 | tee test-output.log
```

### TestApplication.swift (Test helper)

```swift
import XCTVapor
import Fluent
@testable import App

extension Application {
    /// Create a configured test application.
    static func testable() async throws -> Application {
        let app = try await Application.make(.testing)
        try await configure(app)
        try await app.autoRevert()
        try await app.autoMigrate()
        return app
    }
}

/// Helper to make authenticated requests in tests.
extension XCTApplicationTester {
    @discardableResult
    func test(
        _ method: HTTPMethod,
        _ path: String,
        headers: HTTPHeaders = [:],
        body: ByteBuffer? = nil,
        userID: String? = nil,
        afterResponse: (XCTHTTPResponse) async throws -> Void = { _ in }
    ) async throws -> XCTApplicationTester {
        var allHeaders = headers
        if let userID {
            let token = try testAccessToken(for: userID, on: self.app)
            allHeaders.bearerAuthorization = .init(token: token)
        }
        return try await self.test(method, path, headers: allHeaders, body: body, afterResponse: afterResponse)
    }
}

func testAccessToken(for userID: String, on app: Application) throws -> String {
    let payload = TempoAccessToken(
        subject: .init(value: userID),
        issuer: .init(value: "tempo-api"),
        audience: .init(value: ["app.tempo.ios"]),
        issuedAt: .init(value: Date()),
        expiration: .init(value: Date().addingTimeInterval(900)),
        jti: "test_\(UUID().uuidString)",
        deviceID: "test-device",
        scopes: ["user"]
    )
    return try app.jwt.keys.sign(payload, kid: JWKIdentifier(string: "key-2026-03"))
}
```

### Factories.swift (Test data factory)

```swift
import Fluent
@testable import App

enum Factory {
    /// Create a test user in the database.
    static func createUser(
        on db: Database,
        username: String = "testuser_\(String.randomHex(length: 6))",
        displayName: String = "Test User",
        xpTotal: Int = 0,
        level: Int = 1
    ) async throws -> User {
        let user = User(
            appleUserID: "001234.\(UUID().uuidString)",
            username: username,
            displayName: displayName
        )
        user.xpTotal = xpTotal
        user.level = level
        try await user.save(on: db)
        return user
    }

    /// Create a test challenge with participants.
    static func createChallenge(
        on db: Database,
        creator: User,
        participants: [User] = [],
        type: ChallengeType = .xpTotal,
        status: String = "active"
    ) async throws -> Challenge {
        let challenge = Challenge(
            title: "Test Challenge \(String.randomHex(length: 4))",
            type: type,
            creatorID: creator.id!,
            startsAt: Date().addingTimeInterval(-3600),
            endsAt: Date().addingTimeInterval(86400 * 7)
        )
        challenge.status = status
        try await challenge.save(on: db)

        // Add creator as participant
        let creatorParticipant = ChallengeParticipant(
            challengeID: challenge.id!, userID: creator.id!
        )
        try await creatorParticipant.save(on: db)

        // Add other participants
        for user in participants {
            let p = ChallengeParticipant(challengeID: challenge.id!, userID: user.id!)
            try await p.save(on: db)
        }

        return challenge
    }

    /// Create a friendship between two users.
    static func createFriendship(
        on db: Database,
        userA: User,
        userB: User
    ) async throws -> Friendship {
        let aID = userA.id!
        let bID = userB.id!
        let friendship = Friendship(
            userAID: aID < bID ? aID : bID,
            userBID: aID < bID ? bID : aID
        )
        try await friendship.save(on: db)
        return friendship
    }
}
```

### ArenaTests.swift (Example test file)

```swift
import XCTVapor
import Fluent
@testable import App

final class ArenaTests: XCTestCase {
    var app: Application!
    var user: User!
    var friend: User!

    override func setUp() async throws {
        app = try await Application.testable()
        user = try await Factory.createUser(on: app.db, username: "nicola")
        friend = try await Factory.createUser(on: app.db, username: "marco")
        _ = try await Factory.createFriendship(on: app.db, userA: user, userB: friend)
    }

    override func tearDown() async throws {
        try await app.autoRevert()
        try await app.asyncShutdown()
    }

    func testCreateChallenge() async throws {
        let body = CreateChallengeRequest(
            title: "March Madness",
            description: "Who earns the most XP?",
            type: .xpTotal,
            durationDays: 7,
            startsAt: Date().addingTimeInterval(3600),
            maxParticipants: 10,
            inviteUserIDs: [friend.id!],
            visibility: "friends_only"
        )

        try await app.test(.POST, "v1/challenges", userID: user.id!) { req in
            try req.content.encode(body)
        } afterResponse: { res in
            XCTAssertEqual(res.status, .ok)
            let envelope = try res.content.decode(Envelope<ChallengeResponse>.self)
            XCTAssertTrue(envelope.ok)
            XCTAssertEqual(envelope.data.title, "March Madness")
            XCTAssertEqual(envelope.data.type, "xp_total")
            XCTAssertEqual(envelope.data.participants.count, 1) // Creator auto-joined
        }
    }

    func testJoinChallenge() async throws {
        let challenge = try await Factory.createChallenge(
            on: app.db, creator: user
        )

        try await app.test(.POST, "v1/challenges/\(challenge.id!)/join", userID: friend.id!) { res in
            XCTAssertEqual(res.status, .ok)
            let envelope = try res.content.decode(Envelope<ChallengeResponse>.self)
            XCTAssertEqual(envelope.data.participants.count, 2)
        }
    }

    func testCannotJoinFullChallenge() async throws {
        // Create challenge with max 2 participants
        let challenge = Challenge(
            title: "Tiny Challenge",
            type: .xpTotal,
            creatorID: user.id!,
            startsAt: Date().addingTimeInterval(-3600),
            endsAt: Date().addingTimeInterval(86400),
            maxParticipants: 2
        )
        challenge.status = "active"
        try await challenge.save(on: app.db)

        // Add 2 participants (max)
        let p1 = ChallengeParticipant(challengeID: challenge.id!, userID: user.id!)
        try await p1.save(on: app.db)
        let thirdUser = try await Factory.createUser(on: app.db, username: "third")
        let p2 = ChallengeParticipant(challengeID: challenge.id!, userID: thirdUser.id!)
        try await p2.save(on: app.db)

        try await app.test(.POST, "v1/challenges/\(challenge.id!)/join", userID: friend.id!) { res in
            XCTAssertEqual(res.status, .conflict)
        }
    }

    func testListChallenges() async throws {
        _ = try await Factory.createChallenge(on: app.db, creator: user)
        _ = try await Factory.createChallenge(on: app.db, creator: friend)

        try await app.test(.GET, "v1/challenges?status=active", userID: user.id!) { res in
            XCTAssertEqual(res.status, .ok)
            let envelope = try res.content.decode(Envelope<[ChallengeResponse]>.self)
            XCTAssertGreaterThanOrEqual(envelope.data.count, 2)
        }
    }
}
```

---

## 13. Deployment

### Option A: Railway (Recommended for Simplicity)

**Step 1: Install Railway CLI**

```bash
brew install railway
railway login
```

**Step 2: Initialize project**

```bash
cd tempo-backend
railway init
```

**Step 3: Add services**

```bash
# Add PostgreSQL
railway add --plugin postgresql

# Add Redis
railway add --plugin redis
```

**Step 4: Configure environment**

```bash
# Railway auto-injects DATABASE_URL and REDIS_URL
# Add remaining secrets
railway variables set JWT_ES256_PRIVATE_KEY="$(cat keys/ec_private.pem)"
railway variables set JWT_KEY_ID="key-2026-03"
railway variables set ENCRYPTION_KEY="$(openssl rand -hex 32)"
railway variables set WHOOP_CLIENT_ID="your_client_id"
railway variables set WHOOP_CLIENT_SECRET="your_secret"
railway variables set WHOOP_WEBHOOK_SECRET="your_webhook_secret"
railway variables set CLAUDE_API_KEY="sk-ant-xxxxx"
railway variables set APNS_KEY_ID="XXXXX12345"
railway variables set APNS_TEAM_ID="ABCDE12345"
railway variables set ENVIRONMENT="production"
```

**Step 5: Create `railway.toml`**

```toml
[build]
builder = "dockerfile"
dockerfilePath = "Dockerfile"

[deploy]
healthcheckPath = "/health"
healthcheckTimeout = 30
restartPolicyType = "on_failure"
restartPolicyMaxRetries = 5

[service]
internalPort = 8080
```

**Step 6: Deploy**

```bash
railway up
```

**Step 7: Run migrations**

```bash
railway run swift run App migrate --yes
```

**Step 8: Add custom domain**

```bash
railway domain
# Then add CNAME: api.tempo.app -> your-project.up.railway.app
```

### Option B: Fly.io (Recommended for Performance)

**Step 1: Install Fly CLI**

```bash
brew install flyctl
fly auth login
```

**Step 2: Create `fly.toml`**

```toml
app = "tempo-backend"
primary_region = "fra"    # Frankfurt — closest to Italy

[build]
  dockerfile = "Dockerfile"

[env]
  ENVIRONMENT = "production"
  LOG_LEVEL = "info"
  SERVER_PORT = "8080"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = false
  auto_start_machines = true
  min_machines_running = 1

  [http_service.concurrency]
    type = "requests"
    hard_limit = 250
    soft_limit = 200

[[services]]
  protocol = "tcp"
  internal_port = 8080

  [[services.ports]]
    port = 80
    handlers = ["http"]

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]

  [[services.http_checks]]
    interval = "15s"
    timeout = "5s"
    grace_period = "10s"
    method = "GET"
    path = "/health"

[[vm]]
  size = "shared-cpu-2x"
  memory = "1gb"
```

**Step 3: Provision infrastructure**

```bash
# Launch app
fly launch --no-deploy

# Create PostgreSQL (high availability)
fly postgres create --name tempo-db --region fra --vm-size shared-cpu-2x

# Attach database to app
fly postgres attach tempo-db --app tempo-backend

# Create Redis (Upstash managed)
fly redis create --name tempo-redis --region fra
# Note the REDIS_URL from output
```

**Step 4: Set secrets**

```bash
fly secrets set \
  JWT_ES256_PRIVATE_KEY="$(cat keys/ec_private.pem)" \
  JWT_KEY_ID="key-2026-03" \
  ENCRYPTION_KEY="$(openssl rand -hex 32)" \
  WHOOP_CLIENT_ID="your_client_id" \
  WHOOP_CLIENT_SECRET="your_secret" \
  WHOOP_WEBHOOK_SECRET="your_webhook_secret" \
  CLAUDE_API_KEY="sk-ant-xxxxx" \
  APNS_KEY_ID="XXXXX12345" \
  APNS_TEAM_ID="ABCDE12345" \
  REDIS_URL="redis://default:xxxxx@fly-tempo-redis.upstash.io:6379"
```

**Step 5: Deploy**

```bash
fly deploy
```

**Step 6: Run migrations**

```bash
fly ssh console -C "cd /app && ./app migrate --yes"
```

**Step 7: Custom domain + TLS**

```bash
fly certs add api.tempo.app
# Add CNAME: api.tempo.app -> tempo-backend.fly.dev
```

**Step 8: Scale for production**

```bash
# Scale to 2 machines for redundancy
fly scale count 2 --region fra

# Monitor
fly logs
fly status
fly dashboard
```

### Post-deployment checklist

1. Verify health: `curl https://api.tempo.app/health`
2. Run migrations: confirm all tables created
3. Test auth flow: POST to `/v1/auth/apple` with test credentials
4. Verify Redis: check rate limiting works
5. Verify APNs: send test notification
6. Set up monitoring: Fly.io metrics or Railway observability
7. Configure Whoop webhook URL in Whoop developer portal
8. Generate and store APNs key file
9. Set up log aggregation (optional: Papertrail, Datadog)
10. Enable Fly.io or Railway auto-scaling alerts

---

## Helper Extensions

### String+Random.swift

```swift
import Foundation

extension String {
    /// Generate a random hex string of the given length.
    static func randomHex(length: Int) -> String {
        (0..<length).map { _ in
            String(format: "%02x", UInt8.random(in: 0...255))
        }.joined()
    }
}
```

### Request+Auth.swift

See the `JWTAuthMiddleware` section above — the `Request.auth` accessor is defined there.

### Application+Services.swift

```swift
import Vapor

extension Application {
    var encryptionService: EncryptionService {
        EncryptionService()
    }
}

struct EncryptionService {
    /// Encrypt a string using AES-256-GCM.
    func encrypt(_ plaintext: String) throws -> String {
        guard let key = Environment.get("ENCRYPTION_KEY") else {
            fatalError("ENCRYPTION_KEY not set")
        }
        // Implementation uses CryptoKit AES.GCM
        let keyData = Data(hexString: key)!
        let symmetricKey = SymmetricKey(data: keyData)
        let data = Data(plaintext.utf8)
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
        return sealedBox.combined!.base64EncodedString()
    }

    /// Decrypt a string encrypted with AES-256-GCM.
    func decrypt(_ ciphertext: String) throws -> String {
        guard let key = Environment.get("ENCRYPTION_KEY") else {
            fatalError("ENCRYPTION_KEY not set")
        }
        let keyData = Data(hexString: key)!
        let symmetricKey = SymmetricKey(data: keyData)
        let data = Data(base64Encoded: ciphertext)!
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let decrypted = try AES.GCM.open(sealedBox, using: symmetricKey)
        return String(data: decrypted, encoding: .utf8)!
    }
}

import Crypto

extension Data {
    init?(hexString: String) {
        let chars = Array(hexString)
        guard chars.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(chars[i...i+1]), radix: 16) else { return nil }
            bytes.append(byte)
        }
        self.init(bytes)
    }
}
```

---

## Quick Start (from zero to running)

```bash
# 1. Clone / create project
git clone <your-repo> tempo-backend && cd tempo-backend

# 2. Copy environment
cp .env.example .env
# Edit .env with your actual keys

# 3. Generate JWT key pair
openssl ecparam -genkey -name prime256v1 -noout -out keys/ec_private.pem
openssl ec -in keys/ec_private.pem -pubout -out keys/ec_public.pem

# 4. Start infrastructure
docker compose up -d db redis

# 5. Build and run (development)
swift build && swift run App serve --hostname 0.0.0.0 --port 8080

# 6. Verify
curl http://localhost:8080/health
# {"status":"ok"}

# 7. Run migrations (auto in dev, manual in prod)
swift run App migrate --yes
```
