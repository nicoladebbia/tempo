import Fluent
import Vapor

// MARK: - Friend Controller

//
// Per BACKEND_API.md Section 10.6 — Friend system endpoints.
// Per STATE_MACHINES.md Section 9 — Friend Request state machine.
//
// Privacy: a friend sees a display name, a level and a week of XP. Never a
// username, an email, a streak or a user's other data. Strangers see nothing:
// there is no user search and no global list. The only ways to become friends
// are an invite link (instant) and a friend request by user id (accept/decline).

struct FriendController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        // Friend requests
        routes.post("requests", use: sendRequest)
        routes.get("requests", use: listRequests)
        routes.post("requests", ":requestID", "accept", use: acceptRequest)
        routes.post("requests", ":requestID", "decline", use: declineRequest)

        // Invite link: create/reuse mine, kill mine, preview and accept someone's
        routes.post("invite", use: createInvite)
        routes.post("invite", "revoke", use: revokeInvite)
        routes.get("invites", ":token", use: previewInvite)
        routes.post("invites", ":token", "accept", use: acceptInvite)

        // Friends list and management
        routes.get(use: listFriends)
        routes.delete(":friendshipID", use: removeFriend)
    }

    // MARK: - POST /v1/friends/requests

    // Per BACKEND_API.md Section 10.6 — Send friend request.
    // Per STATE_MACHINES.md Section 9 — none -> pendingSent transition.

    @Sendable
    func sendRequest(req: Request) async throws -> Response {
        let userID = try req.auth.requireUserID()
        let body = try req.content.decode(FriendRequestDTO.self)

        // Cannot befriend yourself
        guard body.userId != userID else {
            throw Abort(.badRequest, reason: "Cannot send a friend request to yourself.")
        }

        // Verify target user exists
        guard let target = try await User.find(body.userId, on: req.db), target.deletedAt == nil else {
            throw Abort(.notFound, reason: "User not found.")
        }

        // Check if already friends
        guard try await !ArenaService.areFriends(userID, body.userId, on: req.db) else {
            throw Abort(.conflict, reason: "Already friends.")
        }

        // They already asked me: asking back makes us friends right away.
        if let incoming = try await FriendRequest.query(on: req.db)
            .filter(\.$fromUserID == body.userId)
            .filter(\.$toUserID == userID)
            .filter(\.$status == "pending")
            .first()
        {
            try await ArenaService.befriend(userID, body.userId, on: req.db)
            return try Self.created(
                Self.requestDTO(incoming, status: "accepted", direction: "outgoing", other: target),
                requestID: req.requestID
            )
        }

        // (from, to) is unique, so an old declined or accepted row is reused
        // rather than inserted again: asking twice must not be a server error.
        let existing = try await FriendRequest.query(on: req.db)
            .filter(\.$fromUserID == userID)
            .filter(\.$toUserID == body.userId)
            .first()
        if let existing, existing.status == "pending" {
            throw Abort(.conflict, reason: "Friend request already pending.")
        }
        let friendRequest = existing ?? FriendRequest(fromUserID: userID, toUserID: body.userId)
        friendRequest.status = "pending"
        friendRequest.respondedAt = nil
        try await friendRequest.save(on: req.db)

        return try Self.created(
            Self.requestDTO(friendRequest, direction: "outgoing", other: target),
            requestID: req.requestID
        )
    }

    // MARK: - GET /v1/friends/requests

    // Per BACKEND_API.md Section 10.6 — List pending friend requests.

    @Sendable
    func listRequests(req: Request) async throws -> Envelope<[FriendRequestResponseDTO]> {
        let userID = try req.auth.requireUserID()

        let requests = try await FriendRequest.query(on: req.db)
            .group(.or) { group in
                group.filter(\.$fromUserID == userID)
                group.filter(\.$toUserID == userID)
            }
            .filter(\.$status == "pending")
            .sort(\.$createdAt, .descending)
            .all()

        var dtos: [FriendRequestResponseDTO] = []
        for request in requests {
            let incoming = request.toUserID == userID
            let otherID = incoming ? request.fromUserID : request.toUserID
            guard let other = try await User.find(otherID, on: req.db), other.deletedAt == nil else { continue }
            dtos.append(Self.requestDTO(request, direction: incoming ? "incoming" : "outgoing", other: other))
        }

        return Envelope(data: dtos, requestID: req.requestID)
    }

    // MARK: - POST /v1/friends/requests/:id/accept

    // Per STATE_MACHINES.md Section 9 — pendingReceived -> accepted transition.

    @Sendable
    func acceptRequest(req: Request) async throws -> Envelope<FriendDTO> {
        let userID = try req.auth.requireUserID()
        guard let requestIDString = req.parameters.get("requestID"),
              let requestID = UUID(uuidString: requestIDString)
        else {
            throw Abort(.badRequest, reason: "Valid request ID required.")
        }

        guard let friendRequest = try await FriendRequest.find(requestID, on: req.db) else {
            throw Abort(.notFound, reason: "Friend request not found.")
        }

        // Only the recipient can accept
        guard friendRequest.toUserID == userID else {
            throw Abort(.forbidden, reason: "Only the recipient can accept a friend request.")
        }

        guard friendRequest.status == "pending" else {
            throw Abort(.conflict, reason: "Request is no longer pending.")
        }
        guard let sender = try await User.find(friendRequest.fromUserID, on: req.db), sender.deletedAt == nil else {
            throw Abort(.notFound, reason: "User not found.")
        }

        // befriend() also marks this request accepted.
        let friendship = try await ArenaService.befriend(userID, friendRequest.fromUserID, on: req.db)
        let week = ArenaService.week(containing: req.now, requestedStart: nil)
        return try Envelope(
            data: await Self.friendDTO(friendship, friend: sender, week: week, on: req.db),
            requestID: req.requestID
        )
    }

    // MARK: - POST /v1/friends/requests/:id/decline

    // Per STATE_MACHINES.md Section 9 — pendingReceived -> declined transition.

    @Sendable
    func declineRequest(req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()
        guard let requestIDString = req.parameters.get("requestID"),
              let requestID = UUID(uuidString: requestIDString)
        else {
            throw Abort(.badRequest, reason: "Valid request ID required.")
        }

        guard let friendRequest = try await FriendRequest.find(requestID, on: req.db) else {
            throw Abort(.notFound, reason: "Friend request not found.")
        }

        guard friendRequest.toUserID == userID else {
            throw Abort(.forbidden, reason: "Only the recipient can decline a friend request.")
        }

        guard friendRequest.status == "pending" else {
            throw Abort(.conflict, reason: "Request is no longer pending.")
        }

        friendRequest.status = "declined"
        friendRequest.respondedAt = Date()
        try await friendRequest.save(on: req.db)

        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }

    // MARK: - POST /v1/friends/invite

    // My shareable link. One live link per user: asking again returns the same one.

    @Sendable
    func createInvite(req: Request) async throws -> Envelope<FriendInviteDTO> {
        let userID = try req.auth.requireUserID()
        guard let user = try await User.find(userID, on: req.db) else {
            throw Abort(.notFound, reason: "User not found.")
        }

        let invite: FriendInvite
        if let live = try await FriendInvite.query(on: req.db)
            .filter(\.$userID == userID)
            .filter(\.$revokedAt == nil)
            .first()
        {
            invite = live
        } else {
            invite = FriendInvite(userID: userID, token: FriendInvite.makeToken())
            try await invite.save(on: req.db)
        }

        return Envelope(
            data: FriendInviteDTO(
                token: invite.token,
                url: "\(GroceryShareController.publicBaseURL(req: req))/i/\(invite.token)",
                displayName: ArenaService.publicName(user)
            ),
            requestID: req.requestID
        )
    }

    // MARK: - POST /v1/friends/invite/revoke

    // Kills my link; the next POST /invite makes a fresh one.

    @Sendable
    func revokeInvite(req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()
        let live = try await FriendInvite.query(on: req.db)
            .filter(\.$userID == userID)
            .filter(\.$revokedAt == nil)
            .all()
        for invite in live {
            invite.revokedAt = Date()
            try await invite.save(on: req.db)
        }
        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }

    // MARK: - GET /v1/friends/invites/:token

    // What the person opening a link sees before saying yes.

    @Sendable
    func previewInvite(req: Request) async throws -> Envelope<FriendInvitePreviewDTO> {
        let userID = try req.auth.requireUserID()
        let (_, owner) = try await liveInvite(req)
        let ownerID = try owner.requireID()
        return try Envelope(
            data: FriendInvitePreviewDTO(
                displayName: ArenaService.publicName(owner),
                level: owner.level,
                isOwn: ownerID == userID,
                alreadyFriends: await ArenaService.areFriends(userID, ownerID, on: req.db)
            ),
            requestID: req.requestID
        )
    }

    // MARK: - POST /v1/friends/invites/:token/accept

    // Opening someone's link and saying yes: friends at once. Idempotent.

    @Sendable
    func acceptInvite(req: Request) async throws -> Envelope<FriendDTO> {
        let userID = try req.auth.requireUserID()
        let (_, owner) = try await liveInvite(req)
        let ownerID = try owner.requireID()
        guard ownerID != userID else {
            throw Abort(.badRequest, reason: "That is your own invite link.")
        }
        let friendship = try await ArenaService.befriend(userID, ownerID, on: req.db)
        let week = ArenaService.week(containing: req.now, requestedStart: nil)
        return try Envelope(
            data: await Self.friendDTO(friendship, friend: owner, week: week, on: req.db),
            requestID: req.requestID
        )
    }

    private func liveInvite(_ req: Request) async throws -> (FriendInvite, User) {
        guard let token = req.parameters.get("token"), token.count <= 64,
              let invite = try await FriendInvite.query(on: req.db).filter(\.$token == token).first(),
              invite.isLive,
              let owner = try await User.find(invite.userID, on: req.db), owner.deletedAt == nil
        else {
            // Unknown and revoked look the same: no way to probe which tokens existed.
            throw Abort(.notFound, reason: "This invite link is no longer active.")
        }
        return (invite, owner)
    }

    // MARK: - GET /v1/friends

    // Per BACKEND_API.md Section 10.6 — List friends, with this week's XP.

    @Sendable
    func listFriends(req: Request) async throws -> Envelope<[FriendDTO]> {
        let userID = try req.auth.requireUserID()
        let week = ArenaService.week(containing: req.now, requestedStart: try? req.query.get(String.self, at: "week_start"))

        let friendships = try await Friendship.query(on: req.db)
            .group(.or) { group in
                group.filter(\.$userAID == userID)
                group.filter(\.$userBID == userID)
            }
            .sort(\.$createdAt, .descending)
            .all()

        let friendIDs = friendships.map { $0.userAID == userID ? $0.userBID : $0.userAID }
        let weekly = try await ArenaService.weeklyXP(userIDs: friendIDs, week: week, on: req.db)

        var friends: [FriendDTO] = []
        for friendship in friendships {
            let friendID = friendship.userAID == userID ? friendship.userBID : friendship.userAID
            if let user = try await User.find(friendID, on: req.db), user.deletedAt == nil {
                friends.append(FriendDTO(
                    friendshipID: friendship.id?.uuidString ?? "",
                    userID: friendID,
                    displayName: ArenaService.publicName(user),
                    level: user.level,
                    weeklyXP: weekly[friendID] ?? 0,
                    friendsSince: friendship.createdAt ?? Date()
                ))
            }
        }

        return Envelope(data: friends, requestID: req.requestID)
    }

    // MARK: - DELETE /v1/friends/:friendshipID

    // Per STATE_MACHINES.md Section 9 — accepted -> none transition.

    @Sendable
    func removeFriend(req: Request) async throws -> Envelope<EmptyResponse> {
        let userID = try req.auth.requireUserID()
        guard let friendshipIDString = req.parameters.get("friendshipID"),
              let friendshipID = UUID(uuidString: friendshipIDString)
        else {
            throw Abort(.badRequest, reason: "Valid friendship ID required.")
        }

        guard let friendship = try await Friendship.find(friendshipID, on: req.db) else {
            throw Abort(.notFound, reason: "Friendship not found.")
        }

        // Must be one of the two friends
        guard friendship.userAID == userID || friendship.userBID == userID else {
            throw Abort(.forbidden, reason: "Not your friendship.")
        }

        try await friendship.delete(on: req.db)

        return Envelope(data: EmptyResponse(), requestID: req.requestID)
    }

    // MARK: - Helpers

    static func friendDTO(
        _ friendship: Friendship,
        friend: User,
        week: (start: String, end: String),
        on db: Database
    ) async throws -> FriendDTO {
        let friendID = try friend.requireID()
        let weekly = try await ArenaService.weeklyXP(userIDs: [friendID], week: week, on: db)
        return FriendDTO(
            friendshipID: friendship.id?.uuidString ?? "",
            userID: friendID,
            displayName: ArenaService.publicName(friend),
            level: friend.level,
            weeklyXP: weekly[friendID] ?? 0,
            friendsSince: friendship.createdAt ?? Date()
        )
    }

    static func requestDTO(
        _ request: FriendRequest,
        status: String? = nil,
        direction: String,
        other: User
    ) -> FriendRequestResponseDTO {
        FriendRequestResponseDTO(
            id: request.id?.uuidString ?? "",
            status: status ?? request.status,
            direction: direction,
            displayName: ArenaService.publicName(other),
            level: other.level,
            createdAt: request.createdAt ?? Date()
        )
    }

    private static func created(_ dto: FriendRequestResponseDTO, requestID: String?) throws -> Response {
        try Response(
            status: .created,
            headers: ["Content-Type": "application/json"],
            body: .init(data: JSONEncoder.apiEncoder.encode(Envelope(data: dto, requestID: requestID)))
        )
    }
}

// MARK: - DTOs

/// Decoded by the global `.convertFromSnakeCase` decoder: "user_id" arrives as
/// `userId` (never `userID`), so no CodingKeys here.
struct FriendRequestDTO: Content {
    let userId: String
}

struct FriendRequestResponseDTO: Content {
    let id: String
    let status: String
    /// "incoming" (someone asked me) or "outgoing" (I asked them).
    let direction: String
    /// The other person's display name and level; nothing else about them.
    let displayName: String
    let level: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, direction, level
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

struct FriendDTO: Content {
    let friendshipID: String
    let userID: String
    let displayName: String
    let level: Int
    /// XP earned in the current ISO week (Monday to Sunday).
    let weeklyXP: Int
    let friendsSince: Date

    enum CodingKeys: String, CodingKey {
        case level
        case friendshipID = "friendship_id"
        case userID = "user_id"
        case displayName = "display_name"
        case weeklyXP = "weekly_xp"
        case friendsSince = "friends_since"
    }
}

struct FriendInviteDTO: Content {
    let token: String
    let url: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case token, url
        case displayName = "display_name"
    }
}

struct FriendInvitePreviewDTO: Content {
    let displayName: String
    let level: Int
    let isOwn: Bool
    let alreadyFriends: Bool

    enum CodingKeys: String, CodingKey {
        case level
        case displayName = "display_name"
        case isOwn = "is_own"
        case alreadyFriends = "already_friends"
    }
}

// MARK: - JSON Encoder Extension

extension JSONEncoder {
    static let apiEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()
}
