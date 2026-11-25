import Fluent
import Vapor

// MARK: - Challenge Controller

//
// Per BACKEND_API.md Section 10.7 — Challenge CRUD, join, leave.
// Per STATE_MACHINES.md Section 8 — Challenge state machine.
//
// A challenge is a few friends comparing one number over a run of days. The
// numbers are real: each member's score is summed from the daily totals their
// app pushed (arena_daily_stats), so XP, workouts and study minutes can be
// raced, and nothing else (the server cannot measure the rest, so it does not
// offer it). Dates are whole calendar days ("2026-11-24"); the status
// (upcoming, active, completed) is worked out from them on every read instead
// of being stored, so it can never go stale.

struct ChallengeController: RouteCollection {
    /// What the server can add up from the daily rows.
    static let metrics = ["xp_total", "workout_count", "study_minutes"]

    func boot(routes: RoutesBuilder) throws {
        routes.post(use: create)
        routes.get(use: list)
        routes.get(":challengeID", use: detail)
        routes.post(":challengeID", "join", use: join)
        routes.post(":challengeID", "leave", use: leave)
    }

    // MARK: - POST /v1/challenges

    // Per BACKEND_API.md Section 10.7 — Create a challenge. Only friends can be invited.

    @Sendable
    func create(req: Request) async throws -> Response {
        let userID = try req.auth.requireUserID()
        let body = try req.content.decode(ChallengeCreateDTO.self)

        let title = body.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count >= 3, title.count <= 100 else {
            throw Abort(.badRequest, reason: "Title must be 3-100 characters.")
        }
        guard Self.metrics.contains(body.metric) else {
            throw Abort(.badRequest, reason: "Invalid challenge metric.")
        }
        guard body.durationDays >= 1, body.durationDays <= 90 else {
            throw Abort(.badRequest, reason: "Duration must be 1-90 days.")
        }

        // The first day: the creator's own "today" unless they pick a later one.
        let today = ArenaService.dayString(req.now)
        let earliest = ArenaService.addDays(-1, to: today) ?? today // a phone ahead of the server's UTC day
        let latest = ArenaService.addDays(60, to: today) ?? today
        let startDay = body.startsOn ?? today
        guard ArenaService.parseDay(startDay) != nil, startDay >= earliest, startDay <= latest else {
            throw Abort(.badRequest, reason: "Start day must be today or within the next 60 days.")
        }
        let endDay = ArenaService.addDays(body.durationDays - 1, to: startDay) ?? startDay

        // Max 5 running or upcoming per creator.
        let mine = try await Challenge.query(on: req.db).filter(\.$creatorID == userID).all()
        let running = mine.filter { Self.status(of: $0, today: today) != "completed" }.count
        guard running < 5 else {
            throw Abort(.tooManyRequests, reason: "Too many active challenges (max 5 created per user).")
        }

        let maxParticipants = min(max(body.maxParticipants ?? 10, 2), 50)
        let invitees = Array(Set(body.inviteUserIds ?? [])).filter { $0 != userID }
        guard invitees.count < maxParticipants else {
            throw Abort(.badRequest, reason: "Too many people invited.")
        }
        // Only friends: a challenge must never be a way to reach a stranger.
        let friends = try Set(await ArenaService.friendIDs(of: userID, on: req.db))
        guard invitees.allSatisfy({ friends.contains($0) }) else {
            throw Abort(.forbidden, reason: "You can only invite friends.")
        }

        let challenge = Challenge(
            creatorID: userID,
            title: title,
            description: body.description ?? "",
            type: "group",
            metric: body.metric,
            startDate: ArenaService.parseDay(startDay) ?? req.now,
            endDate: ArenaService.parseDay(endDay) ?? req.now,
            maxParticipants: maxParticipants,
            visibility: "friends_only"
        )
        try await challenge.save(on: req.db)
        let challengeID = try challenge.requireID()

        // Creator auto-joins
        try await ChallengeMember(challengeID: challengeID, userID: userID, status: "joined").save(on: req.db)
        for inviteeID in invitees {
            try await ChallengeMember(challengeID: challengeID, userID: inviteeID, status: "invited").save(on: req.db)
        }

        let created = try await Challenge.query(on: req.db)
            .filter(\.$id == challengeID)
            .with(\.$members)
            .first()
        let dto = try await Self.makeDTO(created ?? challenge, viewerID: userID, today: today, on: req.db)
        return try Response(
            status: .created,
            headers: ["Content-Type": "application/json"],
            body: .init(data: JSONEncoder.apiEncoder.encode(Envelope(data: dto, requestID: req.requestID)))
        )
    }

    // MARK: - GET /v1/challenges

    // Per BACKEND_API.md Section 10.7 — My challenges (joined, invited), newest first.
    // ?status=active|upcoming|completed|all filters on the worked-out status.

    @Sendable
    func list(req: Request) async throws -> Envelope<[ChallengeDetailDTO]> {
        let userID = try req.auth.requireUserID()
        let pagination = try req.query.decode(PaginationQuery.self)
        let limit = min(pagination.limit ?? 25, 100)
        let statusFilter = try? req.query.get(String.self, at: "status")
        let today = ArenaService.dayString(req.now)

        let memberChallengeIDs = try await ChallengeMember.query(on: req.db)
            .filter(\.$userID == userID)
            .filter(\.$status ~~ ["joined", "invited"])
            .all()
            .map { $0.$challenge.id }

        let challenges = try await Challenge.query(on: req.db)
            .filter(\.$id ~~ memberChallengeIDs)
            .sort(\.$createdAt, .descending)
            .with(\.$members)
            .all()

        var dtos: [ChallengeDetailDTO] = []
        for challenge in challenges {
            if let statusFilter, statusFilter != "all", Self.status(of: challenge, today: today) != statusFilter {
                continue
            }
            try dtos.append(await Self.makeDTO(challenge, viewerID: userID, today: today, on: req.db))
            if dtos.count == limit {
                break
            }
        }
        return Envelope(data: dtos, requestID: req.requestID)
    }

    // MARK: - GET /v1/challenges/:id

    // Per BACKEND_API.md Section 10.7 — Challenge detail with standings.

    @Sendable
    func detail(req: Request) async throws -> Envelope<ChallengeDetailDTO> {
        let userID = try req.auth.requireUserID()
        let challenge = try await findChallenge(req)

        // Members and invitees only.
        let mine = challenge.members.first(where: { $0.userID == userID })
        guard let mine, mine.status == "joined" || mine.status == "invited" else {
            throw Abort(.forbidden, reason: "Challenge access denied.")
        }

        let dto = try await Self.makeDTO(challenge, viewerID: userID, today: ArenaService.dayString(req.now), on: req.db)
        return Envelope(data: dto, requestID: req.requestID)
    }

    // MARK: - POST /v1/challenges/:id/join

    // Per STATE_MACHINES.md Section 8 — invited -> accepted. Friends of the creator
    // can also join directly.

    @Sendable
    func join(req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()
        let challenge = try await findChallenge(req)

        guard Self.status(of: challenge, today: ArenaService.dayString(req.now)) != "completed" else {
            throw Abort(.conflict, reason: "Challenge already ended.")
        }

        if let existing = challenge.members.first(where: { $0.userID == userID }) {
            if existing.status == "joined" {
                throw Abort(.conflict, reason: "Already participating.")
            }
            guard challenge.members.filter({ $0.status == "joined" }).count < challenge.maxParticipants else {
                throw Abort(.conflict, reason: "Challenge full.")
            }
            // Someone who left or said no comes back only as a friend of the creator;
            // an invitation stands on its own.
            if existing.status != "invited", existing.userID != challenge.creatorID {
                guard try await ArenaService.areFriends(userID, challenge.creatorID, on: req.db) else {
                    throw Abort(.forbidden, reason: "Challenge access denied (private challenge, not invited).")
                }
            }
            // Invited (or rejoining after leaving): in.
            existing.status = "joined"
            try await existing.save(on: req.db)
            return Envelope(data: EmptyResponse(), requestID: req.requestID)
        }

        guard challenge.members.filter({ $0.status == "joined" }).count < challenge.maxParticipants else {
            throw Abort(.conflict, reason: "Challenge full.")
        }
        // Not invited: only a friend of the creator may walk in.
        guard try await ArenaService.areFriends(userID, challenge.creatorID, on: req.db) else {
            throw Abort(.forbidden, reason: "Challenge access denied (private challenge, not invited).")
        }
        try await ChallengeMember(challengeID: challenge.requireID(), userID: userID, status: "joined").save(on: req.db)
        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }

    // MARK: - POST /v1/challenges/:id/leave

    // Per STATE_MACHINES.md Section 8 — active -> abandoned; an invite becomes declined.

    @Sendable
    func leave(req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()
        let challenge = try await findChallenge(req)

        guard let member = challenge.members.first(where: { $0.userID == userID }),
              member.status == "joined" || member.status == "invited"
        else {
            throw Abort(.conflict, reason: "Not a participant.")
        }
        member.status = member.status == "invited" ? "declined" : "left"
        try await member.save(on: req.db)
        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }

    // MARK: - Helpers

    private func findChallenge(_ req: Request) async throws -> Challenge {
        guard let challengeIDString = req.parameters.get("challengeID"),
              let challengeID = UUID(uuidString: challengeIDString)
        else {
            throw Abort(.badRequest, reason: "Valid challenge ID required.")
        }
        guard let challenge = try await Challenge.query(on: req.db)
            .filter(\.$id == challengeID)
            .with(\.$members)
            .first()
        else {
            throw Abort(.notFound, reason: "Challenge not found.")
        }
        return challenge
    }

    /// upcoming, active or completed, from the challenge's days and `today`.
    static func status(of challenge: Challenge, today: String) -> String {
        let start = ArenaService.dayString(challenge.startDate)
        let end = ArenaService.dayString(challenge.endDate)
        if today < start {
            return "upcoming"
        }
        if today > end {
            return "completed"
        }
        return "active"
    }

    static func metricKeyPath(_ metric: String) -> KeyPath<ArenaDailyStat, Int> {
        switch metric {
        case "workout_count": \.workouts
        case "study_minutes": \.studyMinutes
        default: \.xp
        }
    }

    static func makeDTO(
        _ challenge: Challenge,
        viewerID: String,
        today: String,
        on db: Database
    ) async throws -> ChallengeDetailDTO {
        let startDay = ArenaService.dayString(challenge.startDate)
        let endDay = ArenaService.dayString(challenge.endDate)
        let invitedOrJoined = challenge.members.filter { $0.status == "joined" || $0.status == "invited" }

        // A deleted account is off the board at once, as it is off friends lists.
        let users = try await User.query(on: db)
            .filter(\.$id ~~ invitedOrJoined.map(\.userID))
            .filter(\.$deletedAt == nil)
            .all()
        let usersByID = Dictionary(uniqueKeysWithValues: users.compactMap { user in user.id.map { ($0, user) } })
        let shown = invitedOrJoined.filter { usersByID[$0.userID] != nil }
        let scores = try await ArenaService.totals(
            userIDs: shown.filter { $0.status == "joined" }.map(\.userID),
            from: startDay,
            to: endDay,
            metric: metricKeyPath(challenge.metric),
            on: db
        )

        // Joined members first by score; invited people after, unranked.
        let joined = shown.filter { $0.status == "joined" }
            .map { (member: $0, score: scores[$0.userID] ?? 0) }
            .sorted {
                $0.score != $1.score
                    ? $0.score > $1.score
                    : name(usersByID[$0.member.userID]).localizedCaseInsensitiveCompare(name(usersByID[$1.member.userID])) == .orderedAscending
            }
        let ranks = ArenaService.ranks(for: joined.map(\.score))

        var participants: [ChallengeParticipantDTO] = joined.enumerated().map { index, entry in
            ChallengeParticipantDTO(
                displayName: name(usersByID[entry.member.userID]),
                level: usersByID[entry.member.userID]?.level ?? 1,
                score: entry.score,
                rank: ranks[index],
                isMe: entry.member.userID == viewerID,
                status: "joined"
            )
        }
        // By name, so invited people do not shuffle between refreshes.
        let invited = shown.filter { $0.status == "invited" }.sorted {
            name(usersByID[$0.userID]).localizedCaseInsensitiveCompare(name(usersByID[$1.userID])) == .orderedAscending
        }
        participants += invited.map { member in
            ChallengeParticipantDTO(
                displayName: name(usersByID[member.userID]),
                level: usersByID[member.userID]?.level ?? 1,
                score: 0,
                rank: nil,
                isMe: member.userID == viewerID,
                status: "invited"
            )
        }

        let me = participants.first(where: \.isMe)
        return ChallengeDetailDTO(
            id: challenge.id?.uuidString ?? "",
            isCreator: challenge.creatorID == viewerID,
            title: challenge.title,
            description: challenge.description,
            type: challenge.type,
            metric: challenge.metric,
            startDay: startDay,
            endDay: endDay,
            maxParticipants: challenge.maxParticipants,
            visibility: challenge.visibility,
            status: status(of: challenge, today: today),
            myStatus: me?.status ?? "none",
            myScore: me?.score ?? 0,
            myRank: me?.rank,
            memberCount: joined.count,
            participants: participants,
            createdAt: challenge.createdAt ?? Date()
        )
    }

    private static func name(_ user: User?) -> String {
        user.map(ArenaService.publicName) ?? "Friend"
    }
}

// MARK: - DTOs

/// Request body. Decoded by the global `.convertFromSnakeCase` decoder, so plain
/// camelCase properties (no CodingKeys, no trailing ID acronym).
struct ChallengeCreateDTO: Content {
    let title: String
    let description: String?
    /// One of ChallengeController.metrics.
    let metric: String
    let durationDays: Int
    /// First day, "YYYY-MM-DD" in the creator's calendar. Defaults to today.
    let startsOn: String?
    let maxParticipants: Int?
    /// Friends only; anyone else is refused.
    let inviteUserIds: [String]?
}

struct ChallengeParticipantDTO: Content {
    let displayName: String
    let level: Int
    /// The metric so far, summed over the challenge's days.
    let score: Int
    /// nil while still only invited.
    let rank: Int?
    let isMe: Bool
    /// "joined" or "invited".
    let status: String

    enum CodingKeys: String, CodingKey {
        case level, score, rank, status
        case displayName = "display_name"
        case isMe = "is_me"
    }
}

struct ChallengeDetailDTO: Content {
    let id: String
    let isCreator: Bool
    let title: String
    let description: String
    let type: String
    let metric: String
    /// First and last day, inclusive, "YYYY-MM-DD".
    let startDay: String
    let endDay: String
    let maxParticipants: Int
    let visibility: String
    /// upcoming | active | completed, worked out from the days.
    let status: String
    /// joined | invited | none: what the viewer is in this challenge.
    let myStatus: String
    let myScore: Int
    let myRank: Int?
    let memberCount: Int
    let participants: [ChallengeParticipantDTO]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, description, type, metric, visibility, status, participants
        case isCreator = "is_creator"
        case startDay = "start_day"
        case endDay = "end_day"
        case maxParticipants = "max_participants"
        case myStatus = "my_status"
        case myScore = "my_score"
        case myRank = "my_rank"
        case memberCount = "member_count"
        case createdAt = "created_at"
    }
}
