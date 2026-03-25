import Vapor
import Fluent
import FluentPostgresDriver
import Redis
import Queues
import QueuesRedisDriver

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
    // 5. APNs push notifications (placeholder — keys not needed yet)
    // Configured in Phase 12 when APNs keys are available
    // ─────────────────────────────────────────────────

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

    // Auto-migrate in development
    if app.environment == .development {
        try await app.autoMigrate()
    }

    // ─────────────────────────────────────────────────
    // 8. Routes
    // ─────────────────────────────────────────────────
    try routes(app)
}
