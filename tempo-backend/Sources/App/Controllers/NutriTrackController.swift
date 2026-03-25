import Vapor
import Fluent

// MARK: - NutriTrack Integration Controller
// Per BUILD_PLAN step 11.1 — Connect/disconnect NutriTrack.
// Per INTEGRATION_SPECS.md Section 3.1 — PIN-based auth, stored encrypted.

struct NutriTrackIntegrationController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.post("connect", use: connect)
        routes.delete(use: disconnect)
        routes.get("status", use: status)
    }

    // MARK: - POST /v1/integrations/nutritrack/connect

    /// Connect to user's NutriTrack server.
    /// Per INTEGRATION_SPECS.md Section 3.1:
    ///   1. Validate URL (HTTPS required in production)
    ///   2. Health check the server
    ///   3. Verify PIN via POST /api/pin/verify
    ///   4. Encrypt and store PIN + base URL
    @Sendable
    func connect(req: Request) async throws -> Envelope<NutriTrackConnectResponse> {
        let userID = try req.auth.requireUserID()
        let body = try req.content.decode(NutriTrackConnectRequest.self)

        // Validate PIN format (4-8 digits)
        guard body.pin.count >= 4, body.pin.count <= 8,
              body.pin.allSatisfy(\.isNumber) else {
            throw Abort(.badRequest, reason: "PIN must be 4-8 digits.")
        }

        let integration = try await NutriTrackProxyService.shared.connect(
            baseURL: body.baseURL,
            pin: body.pin,
            userID: userID,
            on: req
        )

        return Envelope(
            data: NutriTrackConnectResponse(
                connected: true,
                baseURL: integration.baseURL
            ),
            requestID: req.requestID
        )
    }

    // MARK: - DELETE /v1/integrations/nutritrack

    /// Disconnect NutriTrack integration.
    @Sendable
    func disconnect(req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()
        try await NutriTrackProxyService.shared.disconnect(userID: userID, on: req)
        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }

    // MARK: - GET /v1/integrations/nutritrack/status

    /// Check NutriTrack connection status.
    @Sendable
    func status(req: Request) async throws -> Envelope<NutriTrackStatusDTO> {
        let userID = try req.auth.requireUserID()
        let statusDTO = try await NutriTrackProxyService.shared.status(
            userID: userID, on: req
        )
        return Envelope(data: statusDTO, requestID: req.requestID)
    }
}

// MARK: - NutriTrack Data Controller
// Per BUILD_PLAN step 11.1 — Proxy endpoints to NutriTrack Flask server.
// Per INTEGRATION_SPECS.md Section 3.3 — Endpoint mapping with Redis cache TTLs.

struct NutriTrackDataController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.get("today", use: today)
        routes.get("macro-balance", use: macroBalance)
        routes.get("weekly-report", use: weeklyReport)
    }

    // MARK: - GET /v1/nutritrack/today
    // Per INTEGRATION_SPECS.md Section 3.3 — Proxy to NutriTrack /api/today.
    // Cache: 2 min TTL.

    @Sendable
    func today(req: Request) async throws -> Response {
        let userID = try req.auth.requireUserID()
        let response = try await NutriTrackProxyService.shared.proxyGet(
            path: "/api/today",
            cacheTTL: 120,
            userID: userID,
            on: req
        )
        return convertToResponse(response, on: req)
    }

    // MARK: - GET /v1/nutritrack/macro-balance
    // Per INTEGRATION_SPECS.md Section 3.3 — Proxy to NutriTrack /api/today/macro-balance.
    // Cache: 2 min TTL.

    @Sendable
    func macroBalance(req: Request) async throws -> Response {
        let userID = try req.auth.requireUserID()
        let response = try await NutriTrackProxyService.shared.proxyGet(
            path: "/api/today/macro-balance",
            cacheTTL: 120,
            userID: userID,
            on: req
        )
        return convertToResponse(response, on: req)
    }

    // MARK: - GET /v1/nutritrack/weekly-report
    // Per INTEGRATION_SPECS.md Section 3.3 — Proxy to NutriTrack /api/week/:date.
    // Cache: 10 min TTL.
    // Query param: ?date=2026-03-25 (defaults to current week).

    @Sendable
    func weeklyReport(req: Request) async throws -> Response {
        let userID = try req.auth.requireUserID()

        // Build NutriTrack path with optional date parameter
        let dateParam = try? req.query.get(String.self, at: "date")
        let path: String
        if let date = dateParam {
            path = "/api/week/\(date)"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            path = "/api/week/\(formatter.string(from: Date()))"
        }

        let response = try await NutriTrackProxyService.shared.proxyGet(
            path: path,
            cacheTTL: 600,
            userID: userID,
            on: req
        )
        return convertToResponse(response, on: req)
    }

    // MARK: - Helpers

    /// Convert a ClientResponse to a Vapor Response, forwarding body and content type.
    private func convertToResponse(_ clientResponse: ClientResponse, on req: Request) -> Response {
        var headers = HTTPHeaders()
        if let contentType = clientResponse.headers.first(name: .contentType) {
            headers.add(name: .contentType, value: contentType)
        } else {
            headers.add(name: .contentType, value: "application/json")
        }
        if let cacheHeader = clientResponse.headers.first(name: "X-Cache") {
            headers.add(name: "X-Cache", value: cacheHeader)
        }

        return Response(
            status: clientResponse.status,
            headers: headers,
            body: clientResponse.body.map { .init(buffer: $0) } ?? .empty
        )
    }
}

// MARK: - Empty Response DTO

struct EmptyResponse: Content {}
