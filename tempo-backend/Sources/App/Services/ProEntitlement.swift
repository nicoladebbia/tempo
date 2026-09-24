import Fluent
import Redis
import Vapor

// MARK: - ProEntitlement

//
// Shared Pro-entitlement lookup, extracted out of SubscriptionMiddleware so
// routes that need to know "is this user Pro (or allowlisted)" WITHOUT the
// full SubscriptionMiddleware behavior (which also enforces the AI-consent
// gate and hard-fails non-Pro users with a 402) can reuse the exact same
// allowlist + subscription logic instead of re-implementing it.
//
// TrainingProgramImportController is the first such caller: it does its own
// entitlement + quota check (Pro/allowlisted = unlimited imports, free =
// 2/month) rather than sitting behind SubscriptionMiddleware.
//
// Both lookups are Redis-cached (5 min TTL) exactly as before — behavior is
// unchanged, this is a pure extraction.

enum ProEntitlement {
    private static let cacheTTLSeconds = 300

    /// True if the user is Pro (active, non-expired subscription) OR
    /// allowlisted via PRO_ALLOWLIST. Does NOT check AI consent — callers
    /// that need the consent gate too should use SubscriptionMiddleware.
    static func isEntitled(userID: String, on req: Request) async throws -> Bool {
        if try await isAllowlisted(userID: userID, on: req) {
            return true
        }
        return try await isUserPro(userID: userID, on: req)
    }

    /// True if the authenticated user matches any entry in the
    /// PRO_ALLOWLIST env var (comma-separated). An entry matches if it
    /// equals the user's `apple_user_id` (exact), `id` (exact), or
    /// `username` (case-insensitive). Empty/unset env var = allowlist
    /// disabled.
    static func isAllowlisted(userID: String, on req: Request) async throws -> Bool {
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

    /// True if the user has an active, non-expired Pro subscription.
    /// Redis-cached for 5 minutes; invalidated by
    /// `Request.invalidateSubscriptionCache(userID:)` on verify/webhook.
    static func isUserPro(userID: String, on req: Request) async throws -> Bool {
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
}
