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
    let auth = v1.grouped("auth")
    try auth.register(collection: AuthController())

    // Protected endpoints — added as controllers are built
    // let protected = v1.grouped(JWTAuthMiddleware())
}
