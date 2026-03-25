import Vapor
@preconcurrency import Redis

// MARK: - Rate Limit Middleware
// Per VAPOR_PROJECT_STRUCTURE.md Section 8 — Redis-based sliding window rate limiter.
// Configurable per-route with different limits, windows, and scopes.

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
            withScoresBetween: (.inclusive(0), .inclusive(windowStart))
        ).get()

        let currentCount = try await request.redis.zcard(of: key).get()

        if currentCount >= limit {
            // Calculate retry-after
            let oldestEntry = try await request.redis.zrangebyscore(
                from: key,
                withScoresBetween: (.inclusive(windowStart), .inclusive(.infinity)),
                limitBy: (offset: 0, count: 1)
            ).get()
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

            throw Abort(.tooManyRequests, headers: headers, reason: "Rate limit exceeded.")
        }

        // Add current request timestamp
        _ = try await request.redis.zadd(
            [(element: RESPValue(from: UUID().uuidString), score: now)],
            to: key
        ).get()
        // Set expiry on the key so it auto-cleans
        _ = try await request.redis.expire(key, after: .seconds(Int64(window.seconds + 10))).get()

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
