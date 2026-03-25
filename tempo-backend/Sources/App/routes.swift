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
}
