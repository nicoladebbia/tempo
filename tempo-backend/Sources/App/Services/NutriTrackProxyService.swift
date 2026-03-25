import Vapor
import Fluent
import Redis

// MARK: - NutriTrack Proxy Service
// Per INTEGRATION_SPECS.md Section 3 — Proxies requests to user's self-hosted NutriTrack Flask server.
// PIN-based auth with session cookies, automatic re-auth on 401, Redis caching.

actor NutriTrackProxyService {

    static let shared = NutriTrackProxyService()

    // Per-user re-auth deduplication: prevent concurrent re-auths for the same user.
    private var reAuthTasks: [String: Task<String, Error>] = [:]

    // MARK: - Connect

    /// Validate NutriTrack server URL, verify PIN, and store integration.
    /// Per INTEGRATION_SPECS.md Section 3.1 — Connection flow.
    func connect(
        baseURL: String,
        pin: String,
        userID: String,
        on req: Request
    ) async throws -> NutriTrackIntegration {
        // 1. Validate URL
        let validatedURL = try validateURL(baseURL, environment: req.application.environment)

        // 2. Health check
        let healthURI = URI(string: "\(validatedURL)/api/health")
        let healthResponse = try await req.client.get(healthURI)
        guard healthResponse.status == .ok else {
            throw Abort(.badGateway, reason: "NutriTrack server health check failed.")
        }

        // 3. Verify PIN
        let sessionCookie = try await verifyPin(
            pin: pin,
            baseURL: validatedURL,
            on: req
        )

        // 4. Check for existing integration
        if let existing = try await NutriTrackIntegration.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first()
        {
            // Update existing
            existing.baseURL = validatedURL
            existing.encryptedPin = try EncryptionService.encryptNutriTrack(pin)
            existing.sessionCookie = sessionCookie
            existing.lastSyncStatus = "connected"
            try await existing.save(on: req.db)

            // Clear cached data
            try await invalidateCache(userID: userID, on: req)

            return existing
        }

        // 5. Create new integration
        let integration = NutriTrackIntegration(
            userID: userID,
            baseURL: validatedURL,
            encryptedPin: try EncryptionService.encryptNutriTrack(pin)
        )
        integration.sessionCookie = sessionCookie
        integration.lastSyncStatus = "connected"
        try await integration.save(on: req.db)

        return integration
    }

    // MARK: - Disconnect

    /// Remove NutriTrack integration for a user.
    func disconnect(userID: String, on req: Request) async throws {
        guard let integration = try await NutriTrackIntegration.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first()
        else {
            throw Abort(.notFound, reason: "NutriTrack not connected.")
        }

        try await integration.delete(on: req.db)
        try await invalidateCache(userID: userID, on: req)
    }

    // MARK: - Proxy Request

    /// Proxy a GET request to the user's NutriTrack server with caching and auto re-auth.
    /// Per INTEGRATION_SPECS.md Section 3.3 — Endpoint mapping with Redis cache.
    func proxyGet(
        path: String,
        cacheTTL: Int,
        userID: String,
        on req: Request
    ) async throws -> ClientResponse {
        // 1. Check Redis cache
        let cacheKey = RedisKey("nutritrack:\(userID):\(path)")
        if let cached = try? await req.redis.get(cacheKey, as: String.self).get() {
            // Return cached response as a synthetic ClientResponse
            var headers = HTTPHeaders()
            headers.add(name: .contentType, value: "application/json")
            headers.add(name: "X-Cache", value: "HIT")
            let buffer = ByteBuffer(string: cached)
            return ClientResponse(status: .ok, headers: headers, body: buffer)
        }

        // 2. Load integration
        guard let integration = try await NutriTrackIntegration.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first()
        else {
            throw Abort(.notFound, reason: "NutriTrack not connected.")
        }

        // 3. Make proxied request
        var response = try await makeProxiedRequest(
            method: .GET,
            path: path,
            integration: integration,
            on: req
        )

        // 4. Handle 401 — transparent re-auth
        if response.status == .unauthorized {
            let newCookie = try await reAuthenticate(
                integration: integration,
                on: req
            )
            integration.sessionCookie = newCookie
            try await integration.save(on: req.db)

            // Retry with new session
            response = try await makeProxiedRequest(
                method: .GET,
                path: path,
                integration: integration,
                on: req
            )

            // If still 401 after re-auth, PIN has changed
            if response.status == .unauthorized {
                integration.lastSyncStatus = "auth_failed"
                try await integration.save(on: req.db)
                throw Abort(.unauthorized, reason: "NutriTrack PIN has changed. Please reconnect.")
            }
        }

        guard response.status == .ok else {
            throw Abort(
                .badGateway,
                reason: "NutriTrack returned status \(response.status.code)."
            )
        }

        // 5. Cache the response body
        if let body = response.body {
            let bodyString = String(buffer: body)
            _ = try? await req.redis.set(cacheKey, to: bodyString).get()
            _ = try? await req.redis.expire(cacheKey, after: .seconds(Int64(cacheTTL))).get()
        }

        // 6. Update sync status
        integration.lastSyncAt = Date()
        integration.lastSyncStatus = "ok"
        try? await integration.save(on: req.db)

        return response
    }

    // MARK: - Status

    /// Check NutriTrack connection status for a user.
    func status(userID: String, on req: Request) async throws -> NutriTrackStatusDTO {
        guard let integration = try await NutriTrackIntegration.query(on: req.db)
            .filter(\.$user.$id == userID)
            .first()
        else {
            return NutriTrackStatusDTO(
                connected: false,
                baseURL: nil,
                lastSyncAt: nil,
                lastSyncStatus: nil
            )
        }

        return NutriTrackStatusDTO(
            connected: true,
            baseURL: integration.baseURL,
            lastSyncAt: integration.lastSyncAt,
            lastSyncStatus: integration.lastSyncStatus
        )
    }

    // MARK: - Private Helpers

    /// Validate NutriTrack URL format.
    /// Per INTEGRATION_SPECS.md Section 3.1 — URL validation rules.
    /// Per BACKEND_API.md — Max 200 chars, SSRF protection for private IPs.
    private func validateURL(_ urlString: String, environment: Environment) throws -> String {
        // Length validation
        guard urlString.count <= 200 else {
            throw Abort(.badRequest, reason: "NutriTrack URL must be 200 characters or fewer.")
        }

        guard let url = URL(string: urlString) else {
            throw Abort(.badRequest, reason: "Invalid NutriTrack URL.")
        }

        // Scheme validation
        guard url.scheme == "https" || (environment == .development && url.scheme == "http") else {
            throw Abort(.badRequest, reason: "NutriTrack URL must use HTTPS.")
        }

        let host = url.host?.lowercased() ?? ""

        // In production, reject localhost, loopback, and private/link-local IPs (SSRF prevention)
        if environment != .development {
            // Localhost / loopback patterns
            let localhostPatterns = ["localhost", "0.0.0.0", "::1", "[::1]"]
            if localhostPatterns.contains(where: { host == $0 }) {
                throw Abort(.badRequest, reason: "Localhost not allowed in production.")
            }

            // 127.0.0.0/8 — full loopback range
            if host.hasPrefix("127.") {
                throw Abort(.badRequest, reason: "Loopback addresses not allowed in production.")
            }

            // 10.0.0.0/8
            if host.hasPrefix("10.") {
                throw Abort(.badRequest, reason: "Private IP addresses not allowed in production.")
            }

            // 192.168.0.0/16
            if host.hasPrefix("192.168.") {
                throw Abort(.badRequest, reason: "Private IP addresses not allowed in production.")
            }

            // 172.16.0.0/12 (172.16.x.x through 172.31.x.x)
            if host.hasPrefix("172.") {
                let parts = host.split(separator: ".")
                if parts.count >= 2, let second = Int(parts[1]),
                   second >= 16, second <= 31 {
                    throw Abort(.badRequest, reason: "Private IP addresses not allowed in production.")
                }
            }

            // 169.254.0.0/16 (link-local)
            if host.hasPrefix("169.254.") {
                throw Abort(.badRequest, reason: "Link-local addresses not allowed in production.")
            }

            // IPv6 unique local (fc00::/7)
            if host.hasPrefix("fc") || host.hasPrefix("fd") {
                throw Abort(.badRequest, reason: "Private IPv6 addresses not allowed in production.")
            }
        }

        // Strip trailing slash
        return urlString.hasSuffix("/")
            ? String(urlString.dropLast())
            : urlString
    }

    /// Verify PIN against NutriTrack server.
    /// Returns the session cookie on success.
    private func verifyPin(
        pin: String,
        baseURL: String,
        on req: Request
    ) async throws -> String {
        let uri = URI(string: "\(baseURL)/api/pin/verify")
        let response = try await req.client.post(uri) { clientReq in
            try clientReq.content.encode(["pin": pin], as: .json)
        }

        guard response.status == .ok else {
            if response.status == .unauthorized {
                throw Abort(.unauthorized, reason: "Invalid NutriTrack PIN.")
            }
            throw Abort(.badGateway, reason: "NutriTrack PIN verification failed.")
        }

        // Extract session cookie from Set-Cookie header
        guard let setCookie = response.headers.first(name: "Set-Cookie") else {
            throw Abort(.badGateway, reason: "NutriTrack did not return a session cookie.")
        }

        return setCookie
    }

    /// Make a proxied HTTP request to NutriTrack with the stored session cookie.
    private func makeProxiedRequest(
        method: HTTPMethod,
        path: String,
        integration: NutriTrackIntegration,
        on req: Request
    ) async throws -> ClientResponse {
        let uri = URI(string: "\(integration.baseURL)\(path)")
        return try await req.client.send(method, to: uri) { clientReq in
            if let cookie = integration.sessionCookie {
                clientReq.headers.add(name: .cookie, value: cookie)
            }
        }
    }

    /// Re-authenticate with NutriTrack by decrypting the stored PIN and verifying.
    /// Deduplicates concurrent re-auth attempts for the same user.
    /// Per INTEGRATION_SPECS.md Section 3.4 — Transparent re-auth on 401.
    private func reAuthenticate(
        integration: NutriTrackIntegration,
        on req: Request
    ) async throws -> String {
        let userID = integration.$user.id

        // Deduplicate concurrent re-auth for same user
        if let existingTask = reAuthTasks[userID] {
            return try await existingTask.value
        }

        let task = Task<String, Error> {
            defer { reAuthTasks[userID] = nil }

            let pin = try integration.pin()
            let newCookie = try await verifyPin(
                pin: pin,
                baseURL: integration.baseURL,
                on: req
            )
            return newCookie
        }

        reAuthTasks[userID] = task
        return try await task.value
    }

    /// Invalidate all cached NutriTrack data for a user.
    private func invalidateCache(userID: String, on req: Request) async throws {
        let keys: [String] = [
            "nutritrack:\(userID):/api/today",
            "nutritrack:\(userID):/api/today/macro-balance",
        ]
        for key in keys {
            _ = try? await req.redis.delete(RedisKey(key)).get()
        }
    }
}

// MARK: - DTOs

struct NutriTrackConnectRequest: Content {
    let baseURL: String
    let pin: String

    enum CodingKeys: String, CodingKey {
        case baseURL = "base_url"
        case pin
    }
}

struct NutriTrackConnectResponse: Content {
    let connected: Bool
    let baseURL: String

    enum CodingKeys: String, CodingKey {
        case connected
        case baseURL = "base_url"
    }
}

struct NutriTrackStatusDTO: Content {
    let connected: Bool
    let baseURL: String?
    let lastSyncAt: Date?
    let lastSyncStatus: String?

    enum CodingKeys: String, CodingKey {
        case connected
        case baseURL = "base_url"
        case lastSyncAt = "last_sync_at"
        case lastSyncStatus = "last_sync_status"
    }
}
