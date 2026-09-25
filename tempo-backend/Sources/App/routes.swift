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
    // JWT auth → ToS gate (451 until tos_accepted_at is set, with carve-outs
    // for /v1/user/me, /v1/user/accept-tos, DELETE /v1/user/me, and
    // /v1/auth/logout). Per LAUNCH_PUNCH_LIST.md §3.5.
    let protected = v1.grouped(JWTAuthMiddleware()).grouped(ToSGateMiddleware())

    // Whoop integration management — per INTEGRATION_SPECS.md Section 1
    try protected.grouped("integrations", "whoop")
        .grouped(RateLimitMiddleware(limit: 10, window: .minutes(1), scope: .user))
        .register(collection: WhoopIntegrationController())

    // Whoop data proxy — per BACKEND_API.md Sections 5.6-5.9
    // GET /v1/whoop/recovery, /sleep, /workouts, /cycles
    try protected.grouped("whoop")
        .grouped(RateLimitMiddleware(limit: 100, window: .minutes(1), scope: .user))
        .register(collection: WhoopDataController())

    // Device token management — per BUILD_PLAN step 12.1
    // POST /v1/devices/register, DELETE /v1/devices/:deviceID
    try protected.grouped("devices")
        .grouped(RateLimitMiddleware(limit: 10, window: .minutes(1), scope: .user))
        .register(collection: DeviceController())

    // Receipt scan pipeline — Phase 3 of nutrition rebuild.
    // Receipt CRUD is free; /structure uses Claude Haiku Vision and is Pro-only.
    // The Pro gate is enforced inside ReceiptController on the /structure handler
    // (not on the whole group) so free users can still list/fetch their existing
    // receipts after a downgrade.
    try protected.grouped("nutrition", "receipts")
        .grouped(RateLimitMiddleware(limit: 30, window: .minutes(1), scope: .user))
        .register(collection: ReceiptController())

    // Food search — GET /v1/foods/search (USDA FoodData Central proxy; the
    // USDA key stays server-side). Free for every signed-in user.
    try protected.grouped("foods")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: FoodController())

    // Nutrition AI endpoints — Phase 7 of nutrition rebuild.
    // POST /v1/nutrition/ai/explain-adjustment, /v1/nutrition/ai/suggest-meal,
    // /v1/nutrition/ai/proxy/text, /v1/nutrition/ai/proxy/vision.
    // All Pro-only per MONETIZATION_STRATEGY.md §3 + INTELLIGENCE_REMEDIATION_PLAN.md §4.
    try protected.grouped("nutrition", "ai")
        .grouped(RateLimitMiddleware(limit: 20, window: .minutes(1), scope: .user))
        .grouped(SubscriptionMiddleware())
        .register(collection: NutritionAIController())

    // ─────────────────────────────────────────────────
    // Arena endpoints — per BACKEND_API.md Section 10
    // ─────────────────────────────────────────────────

    // XP — POST /v1/xp/events, GET /v1/xp/today, /history, /level
    try protected.grouped("xp")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: XPController())

    // Leaderboards — GET /v1/leaderboards/weekly, /monthly, /alltime, /friends
    try protected.grouped("leaderboards")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: LeaderboardController())

    // Friends — POST /v1/friends/requests, GET /v1/friends, etc.
    try protected.grouped("friends")
        .grouped(RateLimitMiddleware(limit: 20, window: .minutes(1), scope: .user))
        .register(collection: FriendController())

    // Challenges — POST /v1/challenges, GET /v1/challenges, join, leave
    try protected.grouped("challenges")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: ChallengeController())

    // Achievements — GET /v1/achievements, /available, POST /check
    try protected.grouped("achievements")
        .grouped(RateLimitMiddleware(limit: 60, window: .minutes(1), scope: .user))
        .register(collection: AchievementController())

    // ─────────────────────────────────────────────────
    // AI Insights — per BUILD_PLAN step 15.1
    // Per AI_INTELLIGENCE_ENGINE.md — 10 AI requests per user per day (enforced in controller)
    // ─────────────────────────────────────────────────

    // Insights — GET /v1/insights/weekly-report, /patterns, /drill-sergeant.
    // Pro-only per MONETIZATION_STRATEGY.md §3.1.
    try protected.grouped("insights")
        .grouped(RateLimitMiddleware(limit: 20, window: .minutes(1), scope: .user))
        .grouped(SubscriptionMiddleware())
        .register(collection: InsightController())

    // ─────────────────────────────────────────────────
    // Subscriptions — per BUILD_PLAN Step 20.1 + INTELLIGENCE_REMEDIATION_PLAN.md §4
    // GET  /v1/subscription/status  (JWT) — current Pro tier + expiry
    // POST /v1/subscription/webhook (no JWT, JWS-verified by Apple)
    // ─────────────────────────────────────────────────
    try v1.grouped("subscription")
        .grouped(RateLimitMiddleware(limit: 30, window: .minutes(1), scope: .user))
        .register(collection: SubscriptionController())

    // ─────────────────────────────────────────────────
    // User profile + AI consent — per AI_INTELLIGENCE_ENGINE.md §11.3
    // GET  /v1/user/me         — current user (tier, consent, displayName)
    // POST /v1/user/ai-consent — record AI consent timestamp
    // ─────────────────────────────────────────────────
    try protected.grouped("user")
        .grouped(RateLimitMiddleware(limit: 20, window: .minutes(1), scope: .user))
        .register(collection: UserController())

    // ─────────────────────────────────────────────────
    // Webhooks (no JWT — verified via HMAC)
    // ─────────────────────────────────────────────────

    // Whoop webhooks — per INTEGRATION_SPECS.md Section 1.4
    // POST /v1/webhooks/whoop — HMAC-SHA256 verified
    try v1.grouped("webhooks", "whoop")
        .grouped(WhoopWebhookMiddleware())
        .register(collection: WhoopWebhookController())
}
