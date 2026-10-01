import Fluent
import Vapor

// MARK: - Test Mode Controller

//
// /v1/test/* — registered ONLY by TestMode.configure (TEMPO_TEST_MODE=1 and
// not production), so these routes don't exist on Railway. No JWT: the
// simulator signs in here instead of through Sign in with Apple.
//
// GET    /v1/test           control page (browser) — TestModeControlPage
// POST   /v1/test/login     {name, simulator_udid?, pro?, ai_consent?, tos?, fresh?, display_name?, timezone?}
// GET    /v1/test/status
// POST   /v1/test/ai        {mode, slow_seconds?}
// GET    /v1/test/pushes    ?user_id= | ?name=
// DELETE /v1/test/pushes    ?user_id= | ?name=
// GET    /v1/test/ai-calls
// GET    /v1/test/users     ?name=   test accounts (newest first)
// GET    /v1/test/faults  · POST {path_prefix, kind, method?, status?, delay_seconds?, remaining?, user_id?} · DELETE (?id=)
// POST   /v1/test/auth      {access_ttl_seconds}   (null/0 = the real 15 min)
// POST   /v1/test/sign-out  ?name=                 revoke every session (refresh tokens) of a test user
// GET/POST /v1/test/clock · POST /v1/test/jobs/run  — see TestModeController+Time
// POST   /v1/test/subscription {name, state, days?} — see TestModeController+Subscription
// POST   /v1/test/persona  {name, persona} · GET /v1/test/shared ?name= — see TestModeController+Persona

struct TestModeController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get { _ in TestModeControlPage.response() }
        routes.post("login", use: login)
        routes.get("status", use: status)
        routes.post("ai", use: setAIMode)
        routes.get("pushes", use: pushes)
        routes.delete("pushes", use: clearPushes)
        routes.get("ai-calls", use: aiCalls)
        routes.get("users", use: users)
        routes.get("faults", use: listFaults)
        routes.post("faults", use: addFault)
        routes.delete("faults", use: clearFaults)
        routes.post("auth", use: setAuth)
        routes.post("sign-out", use: signOut)
        bootTime(routes: routes)
        bootSubscription(routes: routes)
        bootPersona(routes: routes)
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
        /// IANA zone for the user's local-time logic (morning briefing). The
        /// server runs on the same Mac as the simulator, so it defaults to its zone.
        var timezone: String?
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
        let zone = body.timezone ?? TimeZone.current.identifier
        guard TimeZone(identifier: zone) != nil else {
            throw Abort(.badRequest, reason: "Unknown timezone '\(zone)'.")
        }
        user.timezone = zone
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
        let recordingAI: Bool
        /// Feature → number of recorded real replies (AI mode replay).
        let aiRecordings: [String: Int]
        let now: Date
        let clockOffsetSeconds: Double
        let faults: Int
        let accessTtlSeconds: Double
    }

    func status(_ req: Request) async throws -> StatusResponse {
        let state = try Self.state(req)
        return StatusResponse(
            testMode: true,
            aiMode: state.aiMode.rawValue,
            slowSeconds: state.slowSeconds,
            realAIAvailable: TestModeClient.hasRealAnthropicKey,
            pushes: state.pushes(for: nil).count,
            aiCalls: state.aiCalls.count,
            recordingAI: state.recordAI,
            aiRecordings: state.recordings.counts(),
            now: req.now,
            clockOffsetSeconds: state.clockOffset,
            faults: state.faults.all.count,
            accessTtlSeconds: state.accessTokenTTL ?? JWTService.accessTokenTTL
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

    static func state(_ req: Request) throws -> TestModeState {
        guard let state = req.application.testMode else { throw Abort(.notFound) }
        return state
    }

    /// `?user_id=` wins; `?name=` maps a test login name to its user id.
    static func userFilter(_ req: Request) async throws -> String? {
        if let id = req.query[String.self, at: "user_id"] {
            return id
        }
        guard let name = req.query[String.self, at: "name"] else { return nil }
        let user = try await User.query(on: req.db).filter(\.$appleUserID == appleUserID(for: name)).first()
        return user?.id ?? "__none__"
    }

    // MARK: - Users

    struct TestUser: Content {
        let id: String
        let name: String
        let displayName: String
        let pro: Bool
        let createdAt: Date?
        let simulatorUdid: String?
    }

    func users(_ req: Request) async throws -> [TestUser] {
        var query = User.query(on: req.db).filter(\.$appleUserID =~ "test:")
        if let name = req.query[String.self, at: "name"] {
            query = User.query(on: req.db).filter(\.$appleUserID == Self.appleUserID(for: name))
        }
        let rows = try await query.sort(\.$createdAt, .descending).limit(200).all()
        let state = try Self.state(req)
        var out: [TestUser] = []
        for user in rows {
            let id = try user.requireID()
            let name = String(user.appleUserID.dropFirst("test:".count))
            guard !name.contains(":retired:") else { continue }
            let subs = try await UserSubscription.query(on: req.db).filter(\.$user.$id == id).all()
            out.append(TestUser(
                id: id,
                name: name,
                displayName: user.displayName,
                pro: subs.contains { $0.isActive && $0.expirationDate > req.now },
                createdAt: user.createdAt,
                simulatorUdid: state.simulator(for: id)
            ))
        }
        return out
    }

    // MARK: - Faults + auth

    func listFaults(_ req: Request) async throws -> [FaultRule] {
        try Self.state(req).faults.all
    }

    func addFault(_ req: Request) async throws -> FaultRule {
        let rule = try req.content.decode(FaultRule.self)
        guard rule.pathPrefix.hasPrefix("/"), !rule.pathPrefix.hasPrefix("/v1/test") else {
            throw Abort(.badRequest, reason: "path_prefix must start with / and not be /v1/test.")
        }
        return try Self.state(req).faults.add(rule)
    }

    func clearFaults(_ req: Request) async throws -> HTTPStatus {
        let faults = try Self.state(req).faults
        if let id = req.query[UUID.self, at: "id"] {
            faults.remove(id: id)
        } else {
            faults.clear()
        }
        return .noContent
    }

    struct AuthRequest: Content {
        var accessTtlSeconds: Double?
    }

    func setAuth(_ req: Request) async throws -> AuthRequest {
        let body = try req.content.decode(AuthRequest.self)
        let ttl = body.accessTtlSeconds.flatMap { $0 > 0 ? max(5, $0) : nil }
        try Self.state(req).accessTokenTTL = ttl
        return AuthRequest(accessTtlSeconds: ttl ?? JWTService.accessTokenTTL)
    }

    func signOut(_ req: Request) async throws -> HTTPStatus {
        guard let id = try await Self.userFilter(req), id != "__none__" else {
            throw Abort(.notFound, reason: "No such test user.")
        }
        try await JWTService.revokeAllTokens(userID: id, on: req.db)
        return .noContent
    }
}
