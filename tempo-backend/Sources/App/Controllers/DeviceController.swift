import Vapor
import Fluent

// MARK: - Device Controller
// Per BUILD_PLAN step 12.1 — Device token registration endpoints.
// POST /v1/devices/register — Store APNs device token.
// DELETE /v1/devices/:id — Remove device token.

struct DeviceController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.post("register", use: register)
        routes.delete(":deviceID", use: remove)
        routes.post("test-push", use: testPush)
    }

    // MARK: - POST /v1/devices/register
    // Upserts a device token for the authenticated user.
    // If a token already exists for this user + device combination, update it.

    @Sendable
    func register(req: Request) async throws -> Envelope<DeviceTokenResponseDTO> {
        let userID = try req.auth.requireUserID()
        let body = try req.content.decode(DeviceTokenRegisterDTO.self)

        // Validate token format (hex string, 64+ chars)
        guard body.token.count >= 64,
              body.token.allSatisfy({ $0.isHexDigit }) else {
            throw Abort(.badRequest, reason: "Invalid device token format.")
        }

        // Check for existing token for this user + device
        if let existing = try await DeviceToken.query(on: req.db)
            .filter(\.$userID == userID)
            .filter(\.$deviceID == body.deviceID)
            .first()
        {
            // Update existing
            existing.token = body.token
            existing.appVersion = body.appVersion
            existing.deviceName = body.deviceName
            try await existing.save(on: req.db)

            return Envelope(
                data: DeviceTokenResponseDTO(
                    id: existing.id!,
                    registered: true
                ),
                requestID: req.requestID
            )
        }

        // Create new
        let deviceToken = DeviceToken(
            userID: userID,
            token: body.token,
            deviceID: body.deviceID,
            deviceName: body.deviceName,
            appVersion: body.appVersion
        )
        try await deviceToken.save(on: req.db)

        return Envelope(
            data: DeviceTokenResponseDTO(
                id: deviceToken.id!,
                registered: true
            ),
            requestID: req.requestID
        )
    }

    // MARK: - DELETE /v1/devices/:deviceID
    // Remove a device token (e.g., on logout or app uninstall).

    @Sendable
    func remove(req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()
        guard let deviceID = req.parameters.get("deviceID") else {
            throw Abort(.badRequest, reason: "Device ID required.")
        }

        if let token = try await DeviceToken.query(on: req.db)
            .filter(\.$userID == userID)
            .filter(\.$deviceID == deviceID)
            .first()
        {
            try await token.delete(on: req.db)
        }

        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }

    // MARK: - POST /v1/devices/test-push
    // Send a test push notification to verify the APNs pipeline end-to-end.

    @Sendable
    func testPush(req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()

        try await APNsService.sendAlert(
            to: userID,
            title: "TEMPO",
            body: "Push notifications are working. You're locked in.",
            type: .general,
            on: req
        )

        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }
}

// MARK: - DTOs

struct DeviceTokenRegisterDTO: Content {
    let token: String
    let deviceID: String
    let deviceName: String?
    let appVersion: String?

    enum CodingKeys: String, CodingKey {
        case token
        case deviceID = "device_id"
        case deviceName = "device_name"
        case appVersion = "app_version"
    }
}

struct DeviceTokenResponseDTO: Content {
    let id: String
    let registered: Bool
}
