import Vapor

// MARK: - Routes
// Per VAPOR_PROJECT_STRUCTURE.md Section 4 — routes.swift

func routes(_ app: Application) throws {

    // Health check — no auth, no versioning
    // Per BUILD_PLAN 6.1: GET /health returns {"status":"ok"}
    app.get("health") { _ in
        ["status": "ok"]
    }

    // ─────────────────────────────────────────────────
    // API v1
    // Per BACKEND_API.md Section 1 — all endpoints under /v1
    // ─────────────────────────────────────────────────
    let v1 = app.grouped("v1")

    // Auth endpoints — per BACKEND_API.md Section 2
    // POST /v1/auth/apple, /v1/auth/refresh, /v1/auth/logout
    // Rate limited: 10 req/min per IP per BACKEND_API.md
    let auth = v1.grouped("auth")
        .grouped(RateLimitMiddleware(limit: 10, window: .minutes(1), scope: .ip))
    try auth.register(collection: AuthController())

    // ─────────────────────────────────────────────────
    // Protected endpoints (JWT required)
    // ─────────────────────────────────────────────────
    let protected = v1.grouped(JWTAuthMiddleware())

    // Whoop integration management — per INTEGRATION_SPECS.md Section 1
    try protected.grouped("integrations", "whoop")
        .grouped(RateLimitMiddleware(limit: 10, window: .minutes(1), scope: .user))
        .register(collection: WhoopIntegrationController())

    // Whoop data proxy — per BACKEND_API.md Sections 5.6-5.9
    // GET /v1/whoop/recovery, /sleep, /workouts, /cycles
    try protected.grouped("whoop")
        .grouped(RateLimitMiddleware(limit: 100, window: .minutes(1), scope: .user))
        .register(collection: WhoopDataController())

    // NutriTrack integration management — per INTEGRATION_SPECS.md Section 3
    try protected.grouped("integrations", "nutritrack")
        .grouped(RateLimitMiddleware(limit: 10, window: .minutes(1), scope: .user))
        .register(collection: NutriTrackIntegrationController())

    // NutriTrack data proxy — per INTEGRATION_SPECS.md Section 3.3
    // GET /v1/nutritrack/today, /macro-balance, /weekly-report
    try protected.grouped("nutritrack")
        .grouped(RateLimitMiddleware(limit: 100, window: .minutes(1), scope: .user))
        .register(collection: NutriTrackDataController())

    // ─────────────────────────────────────────────────
    // Webhooks (no JWT — verified via HMAC)
    // ─────────────────────────────────────────────────

    // Whoop webhooks — per INTEGRATION_SPECS.md Section 1.4
    // POST /v1/webhooks/whoop — HMAC-SHA256 verified
    try v1.grouped("webhooks", "whoop")
        .grouped(WhoopWebhookMiddleware())
        .register(collection: WhoopWebhookController())
}
