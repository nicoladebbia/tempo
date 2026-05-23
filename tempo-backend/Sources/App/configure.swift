import Vapor
import Fluent
import FluentPostgresDriver
import NIOSSL
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
    var dbConfig: SQLPostgresConfiguration
    if let databaseURL = Environment.get("DATABASE_URL") {
        dbConfig = try SQLPostgresConfiguration(url: databaseURL)
        // Railway (and most managed Postgres providers) ship a self-signed
        // server certificate, so strict cert verification fails the TLS
        // handshake. Switch to encrypted-without-verification when the
        // URL was supplied — the local dev path uses `tls: .disable` and
        // doesn't hit this branch.
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.certificateVerification = .none
        let sslContext = try NIOSSLContext(configuration: tlsConfig)
        dbConfig.coreConfiguration.tls = .require(sslContext)
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
    // 4.5. JWT signers
    // Per ADR-008 + INTELLIGENCE_REMEDIATION_PLAN.md §4.
    //
    // Production should use ES256 with a P-256 private key (per
    // VAPOR_PROJECT_STRUCTURE.md §8). For local dev we accept an HS256
    // shared secret via JWT_SECRET so devs can boot without generating a
    // P-256 keypair. Without this, every authenticated request 500s with
    // "no JWT signers configured".
    // ─────────────────────────────────────────────────
    let jwtSecret = Environment.get("JWT_SECRET") ?? "tempo-dev-only-change-me"
    if app.environment == .production, Environment.get("JWT_SECRET") == nil {
        fatalError("JWT_SECRET must be set in production")
    }
    await app.jwt.keys.add(hmac: .init(stringLiteral: jwtSecret), digestAlgorithm: .sha256)

    // ─────────────────────────────────────────────────
    // 5. APNs push notifications
    // Per BUILD_PLAN step 12.1 — P8 token-based authentication
    // Per ADR-019 — Direct APNs, no third-party push service
    // Per TECHNICAL_FEASIBILITY_AUDIT.md Section 5.4 — apnswift is production-ready
    // ─────────────────────────────────────────────────
    if let rawP8 = Environment.get("APNS_KEY_P8"),
       let keyID = Environment.get("APNS_KEY_ID"),
       let teamID = Environment.get("APNS_TEAM_ID") {

        // Some env-var setters (Railway, Heroku CLI, docker-compose) require
        // multi-line values to be encoded with literal `\n` escape sequences.
        // The PEM parser wants real newlines. Normalize both forms so either
        // works — saves a 2am debugging session on launch night.
        let apnsKeyP8 = rawP8.replacingOccurrences(of: "\\n", with: "\n")

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
    // TempoErrorMiddleware preserves `Abort.identifier` as a `code` field so
    // iOS can distinguish error kinds (e.g. subscription_required vs
    // ai_consent_required) without parsing free-text reason strings.
    // Per INTELLIGENCE_REMEDIATION_PLAN.md §4.
    app.middleware.use(TempoErrorMiddleware(environment: app.environment))

    // ─────────────────────────────────────────────────
    // 7. Migrations (order matters: parent tables first)
    // ─────────────────────────────────────────────────
    app.migrations.add(CreateUsers())
    app.migrations.add(AddAIConsentToUsers())
    app.migrations.add(AddToSAcceptedToUsers())
    app.migrations.add(CreateProcessedAppStoreNotifications())
    app.migrations.add(CreateRefreshTokens())
    app.migrations.add(CreateWhoopIntegrations())
    app.migrations.add(CreateWhoopRecovery())
    app.migrations.add(CreateWhoopSleep())
    app.migrations.add(CreateWhoopWorkouts())
    app.migrations.add(CreateWhoopCycles())
    app.migrations.add(CreateNutriTrackIntegrations())
    app.migrations.add(DropNutriTrackIntegrations())
    app.migrations.add(CreateReceipts())
    app.migrations.add(CreateReceiptLineItems())
    app.migrations.add(CreateDeviceTokens())
    app.migrations.add(CreateUserSubscriptions())
    app.migrations.add(CreateAIMonthlySpend())
    app.migrations.add(CreateAIResponseCache())
    app.migrations.add(CreateUserDailyPlanProfiles())

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

    // Morning briefing job intentionally NOT scheduled. The morning briefing,
    // bedtime nudge, and recovery score duplicate what Whoop already delivers
    // to the user; firing our own would double-notify. See
    // `.plans/notifications-audit.md` §1 (Whoop-overlap removal, iOS + backend).
    // `MorningBriefingJob` struct is retained but no longer registered.
    // app.queues.schedule(MorningBriefingJob())
    //     .every(minutes: 15)

    // Per BUILD_PLAN step 15.2 — Weekly summary job.
    // Per AI_INTELLIGENCE_ENGINE.md Section 6.3 — Sunday 20:00 cache warming.
    app.queues.schedule(WeeklySummaryJob())
        .weekly()
        .on(.sunday)
        .at(.init(integerLiteral: 20), .init(integerLiteral: 0))

    // Per BUILD_PLAN step 14.2 — Leaderboard refresh job.
    // Per BACKEND_API.md Section 26.1 — Refreshes materialized view every 5 min.
    app.queues.schedule(LeaderboardRefreshJob())
        .every(minutes: 5)

    // Per AI_INTELLIGENCE_ENGINE.md §3.4 + INTELLIGENCE_REMEDIATION_PLAN.md §7.4.
    // Drill-sergeant 3-day batch generation. Runs Sun 20:00 (Mon-Wed coverage)
    // and Wed 20:00 (Thu-Sat coverage). Notification scheduler reads the cache
    // when firing pushes, eliminating live Claude calls in the hot path.
    app.queues.schedule(DrillSergeantBatchJob())
        .weekly().on(.sunday).at(.init(integerLiteral: 20), .init(integerLiteral: 0))
    app.queues.schedule(DrillSergeantBatchJob())
        .weekly().on(.wednesday).at(.init(integerLiteral: 20), .init(integerLiteral: 0))

    // Per LAUNCH_PUNCH_LIST.md §3.2 follow-up — drop processed App Store
    // notification UUIDs older than 90 days. Daily at 04:00 UTC.
    app.queues.schedule(ProcessedNotificationsCleanupJob())
        .daily().at(.init(integerLiteral: 4), .init(integerLiteral: 0))

    // ─────────────────────────────────────────────────
    // 9. Routes
    // ─────────────────────────────────────────────────
    try routes(app)
}
