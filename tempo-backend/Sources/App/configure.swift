import Vapor
import Fluent
import FluentPostgresDriver
import Redis
import Queues
import QueuesRedisDriver
import APNS
import APNSCore
import VaporAPNS

// MARK: - Application Configuration
// Per VAPOR_PROJECT_STRUCTURE.md Section 4 — configure.swift

func configure(_ app: Application) async throws {

    // ─────────────────────────────────────────────────
    // 1. Content configuration
    // ─────────────────────────────────────────────────
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.keyEncodingStrategy = .convertToSnakeCase
    ContentConfiguration.global.use(encoder: encoder, for: .json)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    ContentConfiguration.global.use(decoder: decoder, for: .json)

    // Max body size: 1MB JSON (default), 5MB multipart via route-level override
    app.routes.defaultMaxBodySize = "1mb"

    // ─────────────────────────────────────────────────
    // 2. Database — PostgreSQL
    // ─────────────────────────────────────────────────
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
            tls: .disable
        )
    }

    app.databases.use(
        .postgres(configuration: dbConfig),
        as: .psql
    )

    // ─────────────────────────────────────────────────
    // 3. Redis
    // Per VAPOR_PROJECT_STRUCTURE.md Section 4 — Redis for caching and queues
    // ─────────────────────────────────────────────────
    let redisURL = Environment.get("REDIS_URL") ?? "redis://localhost:6379"
    app.redis.configuration = try RedisConfiguration(url: redisURL)

    // ─────────────────────────────────────────────────
    // 4. Background job queue (Redis-backed)
    // Per VAPOR_PROJECT_STRUCTURE.md Section 4 — Queues initialization
    // Job types registered in later phases
    // ─────────────────────────────────────────────────
    try app.queues.use(.redis(url: redisURL))

    // ─────────────────────────────────────────────────
    // 5. APNs push notifications
    // Per BUILD_PLAN step 12.1 — P8 token-based authentication
    // Per ADR-019 — Direct APNs, no third-party push service
    // Per TECHNICAL_FEASIBILITY_AUDIT.md Section 5.4 — apnswift is production-ready
    // ─────────────────────────────────────────────────
    if let apnsKeyP8 = Environment.get("APNS_KEY_P8"),
       let keyID = Environment.get("APNS_KEY_ID"),
       let teamID = Environment.get("APNS_TEAM_ID") {

        // Registers both .production and .development containers
        // so debug builds (sandbox) and release builds (production) both work.
        app.apns.configure(.jwt(
            privateKey: try .loadFrom(string: apnsKeyP8),
            keyIdentifier: keyID,
            teamIdentifier: teamID
        ))

        app.logger.info("APNs configured with key \(keyID) (production + development)")
    } else {
        app.logger.warning("APNs not configured — set APNS_KEY_P8, APNS_KEY_ID, APNS_TEAM_ID env vars")
    }

    // ─────────────────────────────────────────────────
    // 6. Middleware (order matters: first registered = outermost)
    // Per VAPOR_PROJECT_STRUCTURE.md Section 4 — CORS + request logging
    // ─────────────────────────────────────────────────
    app.middleware = .init() // clear defaults

    // Request ID — outermost, ensures every response has X-Request-Id
    app.middleware.use(RequestIdMiddleware())

    // Security headers — HSTS, X-Content-Type-Options, etc.
    app.middleware.use(SecurityHeadersMiddleware())

    // CORS — allow Tempo iOS bundle
    let corsConfig = CORSMiddleware.Configuration(
        allowedOrigin: .all,
        allowedMethods: [.GET, .POST, .PUT, .PATCH, .DELETE, .OPTIONS],
        allowedHeaders: [.accept, .authorization, .contentType, .origin, .xRequestedWith],
        allowCredentials: true,
        exposedHeaders: [.init("X-Request-Id")]
    )
    app.middleware.use(CORSMiddleware(configuration: corsConfig))

    // File serving and error handling
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
    app.middleware.use(ErrorMiddleware.default(environment: app.environment))

    // ─────────────────────────────────────────────────
    // 7. Migrations (order matters: parent tables first)
    // ─────────────────────────────────────────────────
    app.migrations.add(CreateUsers())
    app.migrations.add(CreateRefreshTokens())
    app.migrations.add(CreateWhoopIntegrations())
    app.migrations.add(CreateWhoopRecovery())
    app.migrations.add(CreateWhoopSleep())
    app.migrations.add(CreateWhoopWorkouts())
    app.migrations.add(CreateWhoopCycles())
    app.migrations.add(CreateNutriTrackIntegrations())
    app.migrations.add(CreateDeviceTokens())

    // Arena module — per BUILD_PLAN step 14.1
    app.migrations.add(CreateXPEvents())
    app.migrations.add(CreateFriendships())
    app.migrations.add(CreateChallenges())
    app.migrations.add(CreateAchievements())
    app.migrations.add(CreateWeeklyLeaderboard())
    app.migrations.add(SeedAchievements())

    // Auto-migrate in development
    if app.environment == .development {
        try await app.autoMigrate()
    }

    // ─────────────────────────────────────────────────
    // 8. Background jobs
    // ─────────────────────────────────────────────────
    app.queues.add(WhoopWebhookJob())

    // Per BUILD_PLAN step 12.4 — Morning briefing scheduled job.
    // Runs every 15 minutes, checks which users need their morning briefing.
    app.queues.schedule(MorningBriefingJob())
        .every(minutes: 15)

    // Per BUILD_PLAN step 14.2 — Leaderboard refresh job.
    // Per BACKEND_API.md Section 26.1 — Refreshes materialized view every 5 min.
    app.queues.schedule(LeaderboardRefreshJob())
        .every(minutes: 5)

    // ─────────────────────────────────────────────────
    // 9. Routes
    // ─────────────────────────────────────────────────
    try routes(app)
}
