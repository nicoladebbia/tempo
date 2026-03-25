import Vapor
import Fluent

// MARK: - Challenge Controller
// Per BACKEND_API.md Section 10.7 — Challenge CRUD, join, leave.
// Per STATE_MACHINES.md Section 8 — Challenge state machine.

struct ChallengeController: RouteCollection {

    func boot(routes: RoutesBuilder) throws {
        routes.post(use: create)
        routes.get(use: list)
        routes.get(":challengeID", use: detail)
        routes.post(":challengeID", "join", use: join)
        routes.post(":challengeID", "leave", use: leave)
    }

    // MARK: - POST /v1/challenges
    // Per BACKEND_API.md Section 10.7 — Create a challenge.

    @Sendable
    func create(req: Request) async throws -> Response {
        let userID = try req.auth.requireUserID()
        let body = try req.content.decode(ChallengeCreateDTO.self)

        // Validate title length
        guard body.title.count >= 3, body.title.count <= 100 else {
            throw Abort(.badRequest, reason: "Title must be 3-100 characters.")
        }

        // Validate challenge type
        let validTypes = ["xp_total", "workout_count", "workout_strain", "sleep_score",
                          "study_minutes", "streak_maintain", "nutrition_adherence"]
        guard validTypes.contains(body.type) else {
            throw Abort(.badRequest, reason: "Invalid challenge type.")
        }

        // Validate duration
        guard body.durationDays >= 1, body.durationDays <= 90 else {
            throw Abort(.badRequest, reason: "Duration must be 1-90 days.")
        }

        // Validate start date is in the future
        guard let startsAt = ISO8601DateFormatter().date(from: body.startsAt),
              startsAt > Date() else {
            throw Abort(.badRequest, reason: "Start date must be in the future.")
        }

        // Check active challenge limit (max 5 created per user)
        let activeCount = try await Challenge.query(on: req.db)
            .filter(\.$creatorID == userID)
            .filter(\.$status != "completed")
            .count()
        guard activeCount < 5 else {
            throw Abort(.tooManyRequests, reason: "Too many active challenges (max 5 created per user).")
        }

        let maxParticipants = min(max(body.maxParticipants ?? 10, 2), 50)
        let endDate = startsAt.addingTimeInterval(TimeInterval(body.durationDays * 86400))

        let challenge = Challenge(
            creatorID: userID,
            title: body.title,
            description: body.description ?? "",
            type: "group",
            metric: body.type,
            startDate: startsAt,
            endDate: endDate,
            maxParticipants: maxParticipants,
            visibility: body.visibility ?? "friends_only"
        )
        try await challenge.save(on: req.db)

        // Creator auto-joins
        let creatorMember = ChallengeMember(
            challengeID: challenge.id!,
            userID: userID,
            status: "joined"
        )
        try await creatorMember.save(on: req.db)

        // Invite specified users
        if let inviteIDs = body.inviteUserIDs {
            for inviteUserID in inviteIDs.prefix(49) {
                let member = ChallengeMember(
                    challengeID: challenge.id!,
                    userID: inviteUserID,
                    status: "invited"
                )
                try await member.save(on: req.db)
            }
        }

        let dto = ChallengeDetailDTO(
            id: challenge.id?.uuidString ?? "",
            creatorID: challenge.creatorID,
            title: challenge.title,
            description: challenge.description,
            type: body.type,
            metric: challenge.metric,
            startDate: challenge.startDate,
            endDate: challenge.endDate,
            maxParticipants: challenge.maxParticipants,
            visibility: challenge.visibility,
            status: challenge.status,
            memberCount: 1,
            createdAt: challenge.createdAt ?? Date()
        )

        let response = Envelope(data: dto, requestID: req.requestID)
        return try Response(
            status: .created,
            headers: ["Content-Type": "application/json"],
            body: .init(data: JSONEncoder.apiEncoder.encode(response))
        )
    }

    // MARK: - GET /v1/challenges
    // Per BACKEND_API.md Section 10.7 — List challenges.

    @Sendable
    func list(req: Request) async throws -> Envelope<[ChallengeDetailDTO]> {
        let userID = try req.auth.requireUserID()
        let pagination = try req.query.decode(PaginationQuery.self)
        let limit = min(pagination.limit ?? 25, 100)

        let statusFilter = try? req.query.get(String.self, at: "status")

        // Find challenges where user is a member
        let memberChallengeIDs = try await ChallengeMember.query(on: req.db)
            .filter(\.$userID == userID)
            .all()
            .compactMap { $0.$challenge.id }

        var query = Challenge.query(on: req.db)
            .filter(\.$id ~~ memberChallengeIDs)
            .sort(\.$createdAt, .descending)
            .limit(limit)

        if let status = statusFilter, status != "all" {
            query = query.filter(\.$status == status)
        }

        let challenges = try await query.with(\.$members).all()

        let dtos = challenges.map { c in
            ChallengeDetailDTO(
                id: c.id?.uuidString ?? "",
                creatorID: c.creatorID,
                title: c.title,
                description: c.description,
                type: c.type,
                metric: c.metric,
                startDate: c.startDate,
                endDate: c.endDate,
                maxParticipants: c.maxParticipants,
                visibility: c.visibility,
                status: c.status,
                memberCount: c.members.filter { $0.status == "joined" }.count,
                createdAt: c.createdAt ?? Date()
            )
        }

        return Envelope(data: dtos, requestID: req.requestID)
    }

    // MARK: - GET /v1/challenges/:id
    // Per BACKEND_API.md Section 10.7 — Challenge detail with standings.

    @Sendable
    func detail(req: Request) async throws -> Envelope<ChallengeDetailDTO> {
        let userID = try req.auth.requireUserID()
        guard let challengeIDString = req.parameters.get("challengeID"),
              let challengeID = UUID(uuidString: challengeIDString) else {
            throw Abort(.badRequest, reason: "Valid challenge ID required.")
        }

        guard let challenge = try await Challenge.query(on: req.db)
            .filter(\.$id == challengeID)
            .with(\.$members)
            .first() else {
            throw Abort(.notFound, reason: "Challenge not found.")
        }

        // Authorization: must be participant, creator, or public
        let isMember = challenge.members.contains(where: { $0.userID == userID })
        let isCreator = challenge.creatorID == userID
        guard isMember || isCreator || challenge.visibility == "public" else {
            throw Abort(.forbidden, reason: "Challenge access denied.")
        }

        let dto = ChallengeDetailDTO(
            id: challenge.id?.uuidString ?? "",
            creatorID: challenge.creatorID,
            title: challenge.title,
            description: challenge.description,
            type: challenge.type,
            metric: challenge.metric,
            startDate: challenge.startDate,
            endDate: challenge.endDate,
            maxParticipants: challenge.maxParticipants,
            visibility: challenge.visibility,
            status: challenge.status,
            memberCount: challenge.members.filter { $0.status == "joined" }.count,
            createdAt: challenge.createdAt ?? Date()
        )

        return Envelope(data: dto, requestID: req.requestID)
    }

    // MARK: - POST /v1/challenges/:id/join
    // Per STATE_MACHINES.md Section 8 — invited -> accepted or direct join.

    @Sendable
    func join(req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()
        guard let challengeIDString = req.parameters.get("challengeID"),
              let challengeID = UUID(uuidString: challengeIDString) else {
            throw Abort(.badRequest, reason: "Valid challenge ID required.")
        }

        guard let challenge = try await Challenge.query(on: req.db)
            .filter(\.$id == challengeID)
            .with(\.$members)
            .first() else {
            throw Abort(.notFound, reason: "Challenge not found.")
        }

        // Check not already ended
        guard challenge.status != "completed" else {
            throw Abort(.conflict, reason: "Challenge already ended.")
        }

        // Check if already participating
        if let existingMember = challenge.members.first(where: { $0.userID == userID }) {
            if existingMember.status == "joined" {
                throw Abort(.conflict, reason: "Already participating.")
            }
            // If invited, accept the invite
            existingMember.status = "joined"
            try await existingMember.save(on: req.db)
            return Envelope(data: EmptyResponse(), requestID: req.requestID)
        }

        // Check capacity
        let joinedCount = challenge.members.filter { $0.status == "joined" }.count
        guard joinedCount < challenge.maxParticipants else {
            throw Abort(.conflict, reason: "Challenge full.")
        }

        // Check visibility — only friends can join friends_only
        if challenge.visibility == "friends_only" {
            let isFriend = try await isFriendOf(userID: userID, otherUserID: challenge.creatorID, on: req.db)
            guard isFriend else {
                throw Abort(.forbidden, reason: "Challenge access denied (private challenge, not invited).")
            }
        }

        let member = ChallengeMember(
            challengeID: challengeID,
            userID: userID,
            status: "joined"
        )
        try await member.save(on: req.db)

        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }

    // MARK: - POST /v1/challenges/:id/leave
    // Per STATE_MACHINES.md Section 8 — active -> abandoned transition.

    @Sendable
    func leave(req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()
        guard let challengeIDString = req.parameters.get("challengeID"),
              let challengeID = UUID(uuidString: challengeIDString) else {
            throw Abort(.badRequest, reason: "Valid challenge ID required.")
        }

        guard let challenge = try await Challenge.find(challengeID, on: req.db) else {
            throw Abort(.notFound, reason: "Challenge not found.")
        }

        guard challenge.status != "completed" else {
            throw Abort(.conflict, reason: "Challenge already ended.")
        }

        guard let member = try await ChallengeMember.query(on: req.db)
            .filter(\.$challenge.$id == challengeID)
            .filter(\.$userID == userID)
            .filter(\.$status == "joined")
            .first() else {
            throw Abort(.conflict, reason: "Not a participant.")
        }

        member.status = "left"
        try await member.save(on: req.db)

        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }

    // MARK: - Helpers

    private func isFriendOf(userID: String, otherUserID: String, on db: Database) async throws -> Bool {
        let (a, b) = userID < otherUserID ? (userID, otherUserID) : (otherUserID, userID)
        let friendship = try await Friendship.query(on: db)
            .filter(\.$userAID == a)
            .filter(\.$userBID == b)
            .first()
        return friendship != nil
    }
}

// MARK: - DTOs

struct ChallengeCreateDTO: Content {
    let title: String
    let description: String?
    let type: String
    let durationDays: Int
    let startsAt: String
    let maxParticipants: Int?
    let inviteUserIDs: [String]?
    let visibility: String?

    enum CodingKeys: String, CodingKey {
        case title, description, type, visibility
        case durationDays = "duration_days"
        case startsAt = "starts_at"
        case maxParticipants = "max_participants"
        case inviteUserIDs = "invite_user_ids"
    }
}

struct ChallengeDetailDTO: Content {
    let id: String
    let creatorID: String
    let title: String
    let description: String
    let type: String
    let metric: String
    let startDate: Date
    let endDate: Date
    let maxParticipants: Int
    let visibility: String
    let status: String
    let memberCount: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, description, type, metric, visibility, status
        case creatorID = "creator_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case maxParticipants = "max_participants"
        case memberCount = "member_count"
        case createdAt = "created_at"
    }
}
