import Fluent
import Vapor

// MARK: - Test Mode Controller

//
// /v1/test/* — registered ONLY by TestMode.configure (TEMPO_TEST_MODE=1 and
// not production), so these routes don't exist on Railway. No JWT: the
// simulator signs in here instead of through Sign in with Apple.
//
// POST   /v1/test/login     {name, simulator_udid?, pro?, ai_consent?, tos?, fresh?, display_name?}
// GET    /v1/test/status
// POST   /v1/test/ai        {mode, slow_seconds?}
// GET    /v1/test/pushes    ?user_id= | ?name=
// DELETE /v1/test/pushes    ?user_id= | ?name=
// GET    /v1/test/ai-calls

struct TestModeController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.post("login", use: login)
        routes.get("status", use: status)
        routes.post("ai", use: setAIMode)
        routes.get("pushes", use: pushes)
        routes.delete("pushes", use: clearPushes)
        routes.get("ai-calls", use: aiCalls)
    }

    // MARK: - Login

    struct LoginRequest: Content {
        let name: String
        var simulatorUdid: String?
        var pro: Bool?
        var aiConsent: Bool?
        var tos: Bool?
        /// Retire the existing test user and start a brand-new account.
        var fresh: Bool?
        var displayName: String?
    }

    struct LoginResponse: Content {
        let accessToken: String
        let refreshToken: String
        let tokenType: String
        let expiresIn: Int
        let userId: String
        let created: Bool
    }

    static func appleUserID(for name: String) -> String {
        "test:\(name)"
    }

    static func isValidName(_ name: String) -> Bool {
        name.range(of: #"^[a-z0-9][a-z0-9-]{0,39}$"#, options: .regularExpression) != nil
    }

    func login(_ req: Request) async throws -> LoginResponse {
        let body = try req.content.decode(LoginRequest.self)
        guard Self.isValidName(body.name) else {
            throw Abort(.badRequest, reason: "name must be 1-40 chars of a-z, 0-9 and '-'.")
        }
        guard let deviceID = req.headers.first(name: "X-Device-Id"), !deviceID.isEmpty else {
            throw Abort(.badRequest, reason: "Missing X-Device-Id header.")
        }
        let appleID = Self.appleUserID(for: body.name)

        if body.fresh == true, let old = try await User.query(on: req.db).filter(\.$appleUserID == appleID).first() {
            // Keep the old rows (FKs) but detach them from this name.
            old.appleUserID = "\(appleID):retired:\(Int(Date().timeIntervalSince1970))"
            old.username = "\(old.username)_r\(Int(Date().timeIntervalSince1970) % 100_000)"
            try await old.save(on: req.db)
            try await JWTService.revokeAllTokens(userID: old.requireID(), on: req.db)
        }

        var created = false
        let user: User
        if let existing = try await User.query(on: req.db).filter(\.$appleUserID == appleID).first() {
            user = existing
        } else {
            user = User(
                appleUserID: appleID,
                username: "test_\(body.name.replacingOccurrences(of: "-", with: "_"))_\(Int.random(in: 1000 ... 9999))",
                displayName: body.displayName ?? "Test \(body.name)"
            )
            created = true
        }
        if let displayName = body.displayName {
            user.displayName = displayName
        }
        user.tosAcceptedAt = body.tos == false ? nil : (user.tosAcceptedAt ?? Date())
        user.aiConsentAt = body.aiConsent == false ? nil : (user.aiConsentAt ?? Date())
        try await user.save(on: req.db)
        let userID = try user.requireID()

        try await Self.setPro(body.pro ?? true, userID: userID, on: req)
        await req.invalidateSubscriptionCache(userID: userID)

        req.application.testMode?.setSimulator(body.simulatorUdid, for: userID)

        let tokens = try await JWTService.issueTokenPair(userID: userID, deviceID: deviceID, on: req)
        return LoginResponse(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            tokenType: tokens.tokenType,
            expiresIn: tokens.expiresIn,
            userId: userID,
            created: created
        )
    }

    static func setPro(_ pro: Bool, userID: String, on req: Request) async throws {
        let subs = try await UserSubscription.query(on: req.db).filter(\.$user.$id == userID).all()
        if pro {
            if subs.contains(where: { $0.isActive && $0.expirationDate > Date() }) {
                return
            }
            let sub = UserSubscription(
                userID: userID,
                productId: "tempo_pro_monthly",
                originalTransactionId: "test_\(UUID().uuidString.prefix(12))",
                purchaseDate: Date().addingTimeInterval(-86400),
                expirationDate: Date().addingTimeInterval(365 * 86400),
                environment: "sandbox"
            )
            try await sub.save(on: req.db)
        } else {
            for sub in subs where sub.isActive {
                sub.isActive = false
                sub.expirationDate = Date().addingTimeInterval(-60)
                try await sub.save(on: req.db)
            }
        }
    }

    // MARK: - Status + AI mode

    struct StatusResponse: Content {
        let testMode: Bool
        let aiMode: String
        let slowSeconds: Double
        let realAIAvailable: Bool
        let pushes: Int
        let aiCalls: Int
    }

    func status(_ req: Request) async throws -> StatusResponse {
        let state = try Self.state(req)
        return StatusResponse(
            testMode: true,
            aiMode: state.aiMode.rawValue,
            slowSeconds: state.slowSeconds,
            realAIAvailable: TestModeClient.hasRealAnthropicKey,
            pushes: state.pushes(for: nil).count,
            aiCalls: state.aiCalls.count
        )
    }

    struct AIModeRequest: Content {
        let mode: String
        var slowSeconds: Double?
    }

    func setAIMode(_ req: Request) async throws -> StatusResponse {
        let state = try Self.state(req)
        let body = try req.content.decode(AIModeRequest.self)
        guard let mode = AIMode(rawValue: body.mode) else {
            throw Abort(.badRequest, reason: "mode must be one of: \(AIMode.allCases.map(\.rawValue).joined(separator: ", "))")
        }
        if mode == .real, !TestModeClient.hasRealAnthropicKey {
            throw Abort(.preconditionFailed, reason: "No real ANTHROPIC_API_KEY — start with `scripts/testenv.sh up --real-ai`.")
        }
        state.aiMode = mode
        if let seconds = body.slowSeconds {
            state.slowSeconds = max(0, min(seconds, 120))
        }
        return try await status(req)
    }

    // MARK: - Pushes + AI calls

    func pushes(_ req: Request) async throws -> [CapturedPush] {
        try Self.state(req).pushes(for: await Self.userFilter(req))
    }

    func clearPushes(_ req: Request) async throws -> HTTPStatus {
        try Self.state(req).clearPushes(for: await Self.userFilter(req))
        return .noContent
    }

    func aiCalls(_ req: Request) async throws -> [AICallRecord] {
        try Self.state(req).aiCalls
    }

    // MARK: - Helpers

    private static func state(_ req: Request) throws -> TestModeState {
        guard let state = req.application.testMode else { throw Abort(.notFound) }
        return state
    }

    /// `?user_id=` wins; `?name=` maps a test login name to its user id.
    private static func userFilter(_ req: Request) async throws -> String? {
        if let id = req.query[String.self, at: "user_id"] {
            return id
        }
        guard let name = req.query[String.self, at: "name"] else { return nil }
        let user = try await User.query(on: req.db).filter(\.$appleUserID == appleUserID(for: name)).first()
        return user?.id ?? "__none__"
    }
}
