import Fluent
import Redis
import Vapor

// MARK: - SubscriptionMiddleware
//
// Gates Pro-only routes (AI insights, nutrition AI proxy, receipt structuring).
// Must run AFTER JWTAuthMiddleware — relies on the authenticated user being in
// request storage.
//
// Per AI_INTELLIGENCE_ENGINE.md + MONETIZATION_STRATEGY.md §3 + INTELLIGENCE_REMEDIATION_PLAN.md §4:
//   - Free users get 402 with { error: "subscription_required" } on every gated route.
//   - Pro users without AI consent get 402 with { error: "ai_consent_required" }.
//   - Pro users with consent pass through to the route handler.
//
// Subscription status is cached in Redis for 5 minutes (cheap, scales to many
// concurrent requests per user). Cache is invalidated by SubscriptionController
// on verify/webhook events.

struct SubscriptionMiddleware: AsyncMiddleware {
    private static let cacheTTLSeconds = 300

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        let userID = try request.auth.requireUserID()

        // 0. Allowlist bypass. Comma-separated Apple user IDs in the
        // PRO_ALLOWLIST env var get full access with no subscription and no
        // AI-consent gate — used to grant the operator(s) their own access
        // without a purchase. Empty/unset env var = allowlist disabled.
        if try await isAllowlisted(userID: userID, on: request) {
            return try await next.respond(to: request)
        }

        // 1. Resolve subscription (Redis cache → Postgres fallback).
        let isPro = try await isUserPro(userID: userID, on: request)
        guard isPro else {
            throw subscriptionRequired
        }

        // 2. Enforce AI consent (AI_INTELLIGENCE_ENGINE.md §11.3).
        let hasConsent = try await userHasAIConsent(userID: userID, on: request)
        guard hasConsent else {
            throw aiConsentRequired
        }

        return try await next.respond(to: request)
    }

    // MARK: - Allowlist

    /// True when the authenticated user matches any entry in the
    /// PRO_ALLOWLIST env var (comma-separated). An entry matches if it
    /// equals the user's `apple_user_id` (exact), `id` (exact), or
    /// `username` (case-insensitive) — so the operator can whitelist
    /// themselves by whichever identifier is convenient without a DB
    /// lookup. Empty/unset env var = allowlist disabled.
    private func isAllowlisted(userID: String, on req: Request) async throws -> Bool {
        guard let raw = Environment.get("PRO_ALLOWLIST"), !raw.isEmpty else {
            return false
        }
        let entries = raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !entries.isEmpty else {
            return false
        }
        guard let user = try await User.find(userID, on: req.db) else {
            return false
        }

        let exact = Set(entries)
        if exact.contains(user.appleUserID) {
            return true
        }
        if let id = user.id, exact.contains(id) {
            return true
        }
        let lowerEntries = Set(entries.map { $0.lowercased() })
        return lowerEntries.contains(user.username.lowercased())
    }

    // MARK: - Subscription lookup

    private func isUserPro(userID: String, on req: Request) async throws -> Bool {
        let cacheKey = RedisKey("sub:active:\(userID)")
        if let cached = try await req.redis.get(cacheKey, as: String.self).get() {
            return cached == "1"
        }

        let isActive = try await UserSubscription.query(on: req.db)
            .filter(\.$user.$id == userID)
            .filter(\.$isActive == true)
            .filter(\.$expirationDate > Date())
            .first() != nil

        try await req.redis.setex(
            cacheKey,
            to: isActive ? "1" : "0",
            expirationInSeconds: Self.cacheTTLSeconds
        ).get()

        return isActive
    }

    // MARK: - AI consent lookup

    private func userHasAIConsent(userID: String, on req: Request) async throws -> Bool {
        let cacheKey = RedisKey("ai_consent:\(userID)")
        if let cached = try await req.redis.get(cacheKey, as: String.self).get() {
            return cached == "1"
        }

        guard let user = try await User.find(userID, on: req.db) else {
            return false
        }
        let hasConsent = user.aiConsentAt != nil

        try await req.redis.setex(
            cacheKey,
            to: hasConsent ? "1" : "0",
            expirationInSeconds: Self.cacheTTLSeconds
        ).get()

        return hasConsent
    }

    // MARK: - Structured errors

    private var subscriptionRequired: Abort {
        Abort(
            .paymentRequired,
            headers: [:],
            reason: "Pro subscription required for AI features.",
            identifier: "subscription_required"
        )
    }

    private var aiConsentRequired: Abort {
        Abort(
            .paymentRequired,
            headers: [:],
            reason: "AI consent is required before using AI features.",
            identifier: "ai_consent_required"
        )
    }
}

// MARK: - Cache invalidation helper
//
// Called from SubscriptionController.verify, the webhook handler, and
// UserController.aiConsent so the next AI request sees the change instantly
// instead of waiting up to 5 minutes for the cache to expire.

extension Request {
    func invalidateSubscriptionCache(userID: String) async {
        _ = try? await redis.delete(RedisKey("sub:active:\(userID)")).get()
        _ = try? await redis.delete(RedisKey("ai_consent:\(userID)")).get()
    }
}
